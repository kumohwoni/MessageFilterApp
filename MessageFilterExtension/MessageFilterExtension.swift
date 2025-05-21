//
//  MessageFilterExtension.swift
//  MessageFilterExtension
//

import IdentityLookup
import CoreML


final class MessageFilterExtension: ILMessageFilterExtension {}

extension MessageFilterExtension: ILMessageFilterQueryHandling, ILMessageFilterCapabilitiesQueryHandling {
    func handle(_ capabilitiesQueryRequest: ILMessageFilterCapabilitiesQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterCapabilitiesQueryResponse) -> Void) {
        let response = ILMessageFilterCapabilitiesQueryResponse()
        
        NSLog("[FilterExt] capabilitiesQuery 진입")


        // TODO: Update subActions from ILMessageFilterSubAction enum
        response.transactionalSubActions = []
        response.promotionalSubActions   = []

        completion(response)
    }

    func handle(_ queryRequest: ILMessageFilterQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        // First, check whether to filter using offline data (if possible).
        NSLog("[FilterExt] **queryRequest** 진입 from=\(queryRequest.sender ?? "")")
        let (offlineAction, offlineSubAction) = self.offlineAction(for: queryRequest)

        switch offlineAction {
        case .allow, .junk, .promotion, .transaction:
            // Based on offline data, we know this message should either be Allowed, Filtered as Junk, Promotional or Transactional. Send response immediately.
            let response = ILMessageFilterQueryResponse()
            response.action = offlineAction
            response.subAction = offlineSubAction

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
        
        let groupID = "group.com.messagefilterapp.shared"
        guard let userDefaults = UserDefaults(suiteName: groupID) else {
            NSLog("[MFEXT-DEBUG] ❌ UserDefaults 초기화 실패 for \(groupID)")
            return (.allow, .none)
        }
        NSLog("[MFEXT-DEBUG] ✅ UserDefaults 초기화 성공 for \(groupID)")
        
        // App Group 컨테이너 경로
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            NSLog("[MFEXT-DEBUG] 📂 컨테이너 경로: \(url.path)")
        } else {
            NSLog("[MFEXT-DEBUG] ⚠️ 컨테이너 경로 읽기 실패")
        }
        
        // totalReceivedCount 읽기 전후
        let totalBefore = userDefaults.integer(forKey: "totalReceivedCount")
        NSLog("[MFEXT-DEBUG] 🔢 totalBefore = \(totalBefore)")
        userDefaults.set(totalBefore + 1, forKey: "totalReceivedCount")
        userDefaults.synchronize()
        let totalAfter = userDefaults.integer(forKey: "totalReceivedCount")
        NSLog("[MFEXT-DEBUG] 🔢 totalAfter  = \(totalAfter)")
        
        // 키워드 리스트 & 본문
        let whitelist = userDefaults.stringArray(forKey: "whitelist") ?? []
        let blacklist = userDefaults.stringArray(forKey: "blacklist") ?? []
        let body = queryRequest.messageBody ?? ""
        NSLog("[MFEXT-DEBUG] ✉️ 본문: \"\(body)\"")
        NSLog("[MFEXT-DEBUG] ⚪️ whitelist = \(whitelist)")
        NSLog("[MFEXT-DEBUG] ⚫️ blacklist = \(blacklist)")
        
        // 화이트리스트 검사
        if whitelist.contains(where: { body.lowercased().contains($0.lowercased()) }) {
            NSLog("[MFEXT-DEBUG] ✅ 화이트리스트 매칭 → allow")
            return (.allow, .none)
        }
        // 블랙리스트 검사
        if blacklist.contains(where: { body.lowercased().contains($0.lowercased()) }) {
            NSLog("[MFEXT-DEBUG] ✅ 블랙리스트 매칭 → junk")
            return (.junk, .none)
        }

        // ML 분기 시도
        NSLog("[MFEXT-DEBUG] 🤖 ML 분기 시도 시작")
        if let vocab = WordPieceTokenizer.loadVocab(from: "vocab.txt") {
            NSLog("[MFEXT-DEBUG] 🤖 vocab 로드 성공, 크기 = \(vocab.count)")
            
            let tokenizer = WordPieceTokenizer(vocab: vocab)
            let (inputIds, attentionMask) = tokenizer.tokenize(queryRequest.messageBody ?? "")
            NSLog("[MFEXT-DEBUG] 🤖 토큰화 완료, inputIds=\(inputIds), mask=\(attentionMask)")

            guard
                let inputArray  = MLMultiArray.from(inputIds),
                let maskArray   = MLMultiArray.from(attentionMask),
                let modelURL    = Bundle.main.url(forResource: "Model", withExtension: "mlpackage"),
                let model       = try? MLModel(contentsOf: modelURL)
            else {
                NSLog("[MFEXT-DEBUG] ⚠️ ML 입력 변환 또는 모델 로드 실패")
                NSLog("[MFEXT-DEBUG] 🚦 기본 분기 → allow")
                return (.allow, .none)
            }
            NSLog("[MFEXT-DEBUG] 🤖 ML 모델 로드 성공 from \(modelURL.lastPathComponent)")

            let features = try? MLDictionaryFeatureProvider(dictionary: [
                "input_ids":      inputArray,
                "attention_mask": maskArray
            ])
            if let pred = try? model.prediction(from: features!),
               let label = pred.featureValue(for: "classLabel")?.stringValue {
                NSLog("[MFEXT-DEBUG] 🤖 ML 예측 label = \(label)")
                if label == "LABEL_1" {
                    NSLog("[MFEXT-DEBUG] 🤖 ML 분기 → junk")
                    let junkCount = userDefaults.integer(forKey: "junkCount")
                    userDefaults.set(junkCount + 1, forKey: "junkCount")
                    return (.junk, .none)
                } else {
                    NSLog("[MFEXT-DEBUG] 🤖 ML 분기 → allow")
                    let allowCount = userDefaults.integer(forKey: "allowCount")
                    userDefaults.set(allowCount + 1, forKey: "allowCount")
                    return (.allow, .none)
                }
            } else {
                NSLog("[MFEXT-DEBUG] ⚠️ ML 예측 실패")
                NSLog("[MFEXT-DEBUG] 🚦 기본 분기 → allow")
                return (.allow, .none)
            }
        } else {
            NSLog("[MFEXT-DEBUG] ⚠️ vocab.txt 로드 실패")
            NSLog("[MFEXT-DEBUG] 🚦 기본 분기 → allow")
            return (.allow, .none)
        }
    }




    private func networkAction(for networkResponse: ILNetworkResponse) -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        // TODO: Replace with logic to parse the HTTP response and data payload of `networkResponse` to return an action.
        return (.none, .none)
    }

}
