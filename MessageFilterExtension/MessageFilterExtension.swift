import IdentityLookup
import CoreML
import os

private let logger = Logger(subsystem: "com.messagefilterapp", category: "FilterExt")

final class MessageFilterExtension: ILMessageFilterExtension {
    // 1. 모델과 vocab은 static으로 한 번만 로드
    private static let mlConfig: MLModelConfiguration = {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        return cfg
    }()
    
    private static let model: Model = {
        do {
            return try Model(configuration: mlConfig)
        } catch {
            fatalError("ML 모델 로드 실패: \(error)")
        }
    }()
    
    private static let vocab: [String: Int] = {
        guard let v = WordPieceTokenizer.loadVocab(from: "vocab.txt") else {
            logger.error("vocab.txt 로드 실패")
            return [:]
        }
        return v
    }()
}

extension MessageFilterExtension: ILMessageFilterQueryHandling, ILMessageFilterCapabilitiesQueryHandling {
    func handle(_ capabilitiesQueryRequest: ILMessageFilterCapabilitiesQueryRequest,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterCapabilitiesQueryResponse) -> Void) {
        let response = ILMessageFilterCapabilitiesQueryResponse()
        #if DEBUG
        logger.debug("capabilitiesQuery 진입")
        #endif
        
        response.transactionalSubActions = []
        response.promotionalSubActions   = []
        completion(response)
    }

    func handle(_ queryRequest: ILMessageFilterQueryRequest,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        #if DEBUG
        logger.debug("queryRequest 진입 from=\(queryRequest.sender ?? "")")
        #endif
        
        let (offlineAction, offlineSub) = self.offlineAction(for: queryRequest)
        switch offlineAction {
        case .allow, .junk, .promotion, .transaction:
            let resp = ILMessageFilterQueryResponse()
            resp.action = offlineAction
            resp.subAction = offlineSub
            completion(resp)
        case .none:
            context.deferQueryRequestToNetwork() { networkResponse, error in
                let resp = ILMessageFilterQueryResponse()
                resp.action = .none
                resp.subAction = .none
                
                if let net = networkResponse {
                    resp.action = self.networkAction(for: net).0
                    resp.subAction = self.networkAction(for: net).1
                } else {
                    logger.error("네트워크 연기 실패: \(String(describing: error))")
                }
                completion(resp)
            }
        @unknown default:
            let resp = ILMessageFilterQueryResponse()
            resp.action = .none
            resp.subAction = .none
            completion(resp)
        }
    }

    private func offlineAction(for queryRequest: ILMessageFilterQueryRequest)
    -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        let groupID = "group.com.messagefilterapp.shared"
        guard let userDefaults = UserDefaults(suiteName: groupID) else {
            logger.error("UserDefaults 초기화 실패 for \(groupID)")
            return (.allow, .none)
        }
        #if DEBUG
        logger.debug("UserDefaults 초기화 성공 for \(groupID)")
        #endif
        
        // 통계 업데이트
        let total = userDefaults.integer(forKey: "totalReceivedCount") + 1
        userDefaults.set(total, forKey: "totalReceivedCount")
        
        // 화이트/블랙리스트 검사
        let whitelist = userDefaults.stringArray(forKey: "whitelist") ?? []
        let blacklist = userDefaults.stringArray(forKey: "blacklist") ?? []
        let body = queryRequest.messageBody?.lowercased() ?? ""
        
        if whitelist.contains(where: { body.contains($0.lowercased()) }) {
            #if DEBUG
            logger.debug("화이트리스트 매칭 → allow")
            #endif
            return (.allow, .none)
        }
        if blacklist.contains(where: { body.contains($0.lowercased()) }) {
            #if DEBUG
            logger.debug("블랙리스트 매칭 → junk")
            #endif
            return (.junk, .none)
        }
        
        // 4. 타입-세이프 CoreML 인터페이스 + 5. do-catch
        guard !Self.vocab.isEmpty else {
            return (.allow, .none)
        }
        let tokenizer = WordPieceTokenizer(vocab: Self.vocab)
        let (inputIds, attentionMask) = tokenizer.tokenize(queryRequest.messageBody ?? "")
        
        do {
            guard let inputArray = MLMultiArray.from(inputIds),
                  let maskArray  = MLMultiArray.from(attentionMask) else {
                logger.error("MLMultiArray 변환 실패")
                return (.allow, .none)
            }

            let modelInput = ModelInput(input_ids: inputArray,
                                        attention_mask: maskArray)
            
            let output = try Self.model.prediction(input: modelInput)
            let label = output.classLabel
            
            #if DEBUG
            logger.debug("ML 예측 label=\(label)")
            #endif
            
            if label == "LABEL_1" {
                let cnt = userDefaults.integer(forKey: "junkCount") + 1
                userDefaults.set(cnt, forKey: "junkCount")
                return (.junk, .none)
            } else {
                let cnt = userDefaults.integer(forKey: "allowCount") + 1
                userDefaults.set(cnt, forKey: "allowCount")
                return (.allow, .none)
            }
        } catch {
            logger.error("ML 처리 오류: \(error)")
            return (.allow, .none)
        }
    }

    private func networkAction(for networkResponse: ILNetworkResponse)
    -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        // 네트워크 필터링 로직이 필요 없다면 .none 리턴
        logger.debug("networkAction 호출됨")
        return (.none, .none)
    }
}
