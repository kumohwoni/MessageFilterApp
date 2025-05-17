//
//  MessageFilterExtension.swift
//  MessageFilterExtension
//
//  Created by 문다름 on 5/17/25.
//

import IdentityLookup

final class MessageFilterExtension: ILMessageFilterExtension {}

extension MessageFilterExtension: ILMessageFilterQueryHandling, ILMessageFilterCapabilitiesQueryHandling {
    func handle(_ capabilitiesQueryRequest: ILMessageFilterCapabilitiesQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterCapabilitiesQueryResponse) -> Void) {
        let response = ILMessageFilterCapabilitiesQueryResponse()

        // TODO: Update subActions from ILMessageFilterSubAction enum
        // response.transactionalSubActions = [...]
        // response.promotionalSubActions   = [...]

        completion(response)
    }

    func handle(_ queryRequest: ILMessageFilterQueryRequest, context: ILMessageFilterExtensionContext, completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        // First, check whether to filter using offline data (if possible).
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
        let userDefaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")  // 너의 App Group ID
        
        let total = userDefaults?.integer(forKey: "totalReceivedCount") ?? 0
        userDefaults?.set(total + 1, forKey: "totalReceivedCount")
        
        let whitelist = userDefaults?.stringArray(forKey: "whitelist") ?? []
        let blacklist = userDefaults?.stringArray(forKey: "blacklist") ?? []

        let messageBody = queryRequest.messageBody?.lowercased() ?? ""
        
        // 화이트리스트 단어가 포함되면 허용
        if whitelist.contains(where: { messageBody.contains($0.lowercased()) }) {
            let allow = userDefaults?.integer(forKey: "allowCount") ?? 0
            userDefaults?.set(allow + 1, forKey: "allowCount")
            return (.allow, .none)
        }

        // 블랙리스트 단어가 포함되면 무조건 junk 처리
        if blacklist.contains(where: { messageBody.contains($0.lowercased()) }) {
            let junk = userDefaults?.integer(forKey: "junkCount") ?? 0
            userDefaults?.set(junk + 1, forKey: "junkCount")
            return (.junk, .none)
        }
        
        // 아무 것도 해당 안 되면 그냥 필터링 (기본값: none)
        return (.none, .none)
    }



    private func networkAction(for networkResponse: ILNetworkResponse) -> (ILMessageFilterAction, ILMessageFilterSubAction) {
        // TODO: Replace with logic to parse the HTTP response and data payload of `networkResponse` to return an action.
        return (.none, .none)
    }

}
