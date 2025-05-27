//
//  MessageFilterExtension.swift
//  MyAppMessageFilterExtension
//

import IdentityLookup
import CoreML
import CoreFoundation


final class MessageFilterExtension: ILMessageFilterExtension {}

// MARK: - 모델·vocab 초기화
extension MessageFilterExtension {
    /// 모델 파일명이 Model.mlpackage → 클래스명 Model
    private static let spamModel: Model = {
        do {
            return try Model(configuration: MLModelConfiguration())
        } catch {
            fatalError("Core ML 모델 로드 실패: \(error)")
        }
    }()

    /// token → index 맵으로 변환
    private static let vocab: [String: Int] = {
        // MessageFilterExtension.swift, vocab 로딩 부분
        let bundle = Bundle(for: MessageFilterExtension.self)
        guard let url = bundle.url(forResource: "vocab", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("vocab.txt 로드 실패")
            return [:]
        }

        let tokens = text.split(whereSeparator: \.isNewline).map(String.init)
        return Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($1, $0) })
    }()
}

extension MessageFilterExtension: ILMessageFilterQueryHandling, ILMessageFilterCapabilitiesQueryHandling {
    
    func handle(_ capabilitiesQueryRequest: ILMessageFilterCapabilitiesQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterCapabilitiesQueryResponse) -> Void) {
        let response = ILMessageFilterCapabilitiesQueryResponse()
        // 기본 설정으로 모든 메시지 타입에 대해 필터링 가능하도록 설정
        response.transactionalSubActions = []
        response.promotionalSubActions = []
        completion(response)
    }
    
    func handle(_ queryRequest: ILMessageFilterQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        // 통계 업데이트 (전체 메시지 수 증가)
        updateTotalMessageCount()
        
        // First, check whether to filter using offline data (if possible).
        let (offlineAction, offlineSubAction) = self.offlineAction(for: queryRequest)
        
        switch offlineAction {
        case .allow, .junk, .promotion, .transaction:
            // Based on offline data, we know this message should either be Allowed, Filtered as Junk, Promotional or Transactional. Send response immediately.
            let response = ILMessageFilterQueryResponse()
            response.action = offlineAction
            response.subAction = offlineSubAction
            
            // 차단된 메시지인 경우 통계 업데이트
            if offlineAction == .junk {
                updateBlockedMessageCount()
            }
            
            completion(response)
            
        case .none:
            // Based on offline data, we do not know whether this message should be Allowed or Filtered. Defer to network.
            // Note: Deferring requests to network requires the extension target's Info.plist to contain a key with a URL to use. See documentation for details.
            context.deferQueryRequestToNetwork() { (networkResponse, error) in
                let response = ILMessageFilterQueryResponse()
                response.action = .none
                response.subAction = .none
                
                if let networkResponse = networkResponse {
                    // If we received a network response, parse it to determine an action to return in our response.
                    (response.action, response.subAction) = self.networkAction(for: networkResponse)
                    
                    // 네트워크 응답으로 차단된 경우 통계 업데이트
                    if response.action == .junk {
                        self.updateBlockedMessageCount()
                    }
                } else {
                    NSLog("Error deferring query request to network: \(String(describing: error))")
                }
                
                completion(response)
            }
            
        @unknown default:
            break
        }
    }
    
    private func offlineAction(for queryRequest: ILMessageFilterQueryRequest) -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        guard let messageBody = queryRequest.messageBody else {
            return (.none, .none)
        }
        
        let sender = queryRequest.sender ?? ""
        
        // 화이트리스트 확인 (우선순위 높음)
        if isWhitelisted(messageBody: messageBody, sender: sender) {
            return (.allow, .none)
        }
        
        // 블랙리스트 확인
        if isBlacklisted(messageBody: messageBody, sender: sender) {
            return (.junk, .none)
        }
        
        // 기본 스팸 패턴 확인
        if isSpamMessage(messageBody: messageBody, sender: sender) {
            return (.junk, .none)
        }
        
        // 판단할 수 없는 경우
        return (.allow, .none)
    }
    
    private func networkAction(for networkResponse: ILNetworkResponse) -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        // TODO: 네트워크 응답을 파싱하여 스팸 여부 판단
        // 현재는 기본 동작으로 설정
        return (.none, .none)
    }
    
    // MARK: - 화이트리스트 확인
    private func isWhitelisted(messageBody: String, sender: String) -> Bool {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        guard let whitelist = defaults?.stringArray(forKey: "whitelist") else {
            return false
        }
        
        let lowercaseBody = messageBody.lowercased()
        let lowercaseSender = sender.lowercased()
        
        for keyword in whitelist {
            let lowercaseKeyword = keyword.lowercased()
            if lowercaseBody.contains(lowercaseKeyword) || lowercaseSender.contains(lowercaseKeyword) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - 블랙리스트 확인
    private func isBlacklisted(messageBody: String, sender: String) -> Bool {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        guard let blacklist = defaults?.stringArray(forKey: "blacklist") else {
            return false
        }
        
        let lowercaseBody = messageBody.lowercased()
        let lowercaseSender = sender.lowercased()
        
        for keyword in blacklist {
            let lowercaseKeyword = keyword.lowercased()
            if lowercaseBody.contains(lowercaseKeyword) || lowercaseSender.contains(lowercaseKeyword) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Core ML로 스팸 여부 판정
    private func isSpamMessage(messageBody: String, sender: String) -> Bool {
        guard !Self.vocab.isEmpty else { return false }
        let (inputIds, attentionMask) = WordPieceTokenizer(vocab: Self.vocab)
                                          .tokenize(messageBody)

        guard let idsArr  = MLMultiArray.from(inputIds),
              let maskArr = MLMultiArray.from(attentionMask) else {
            print("MLMultiArray 변환 실패")
            return false
        }
        do {
            let input  = ModelInput(input_ids: idsArr, attention_mask: maskArr)
            let output = try Self.spamModel.prediction(input: input)
            return output.classLabel == "LABEL_1"
        } catch {
            print("Core ML 예측 오류:", error)
            return false
        }
    }
    
    
    // MARK: - 통계 업데이트
    
    private func updateTotalMessageCount() {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        let currentCount = defaults?.integer(forKey: "totalReceivedCount") ?? 0
        defaults?.set(currentCount + 1, forKey: "totalReceivedCount")
    }
    
    private func updateBlockedMessageCount() {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        let currentCount = defaults?.integer(forKey: "junkCount") ?? 0
        defaults?.set(currentCount + 1, forKey: "junkCount")
    }
}
