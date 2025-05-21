//
//  ContentView.swift
//  MessageFilterApp
//
import SwiftUI

struct ContentView: View {
    @State private var localSpamFilterOn = true
    @State private var advancedSpamFilterOn = false

    @AppStorage("totalReceivedCount", store: UserDefaults(suiteName: "group.com.messagefilterapp.shared")!)
    private var totalMessages: Int = 0
    @AppStorage("junkCount", store: UserDefaults(suiteName: "group.com.messagefilterapp.shared")!)
    private var blockedMessages: Int = 0

    var spamRate: Double {
        Double(blockedMessages) / max(Double(totalMessages), 1.0)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    Spacer().frame(height: 10)
                    // Toggle Section
                    ToggleCard(title: "로컬 스팸 차단", subtitle: "오프라인에서도 AI를 통해 스팸을 필터링할 수 있어요.", isOn: $localSpamFilterOn)
                    
                    ToggleCard(title: "고급 스팸 차단", subtitle: "데이터를 서버로 전송하여 더 정확하게 필터링해요.", isOn: $advancedSpamFilterOn)

                    // 통계
                    VStack(alignment: .leading, spacing: 10) {

                        Text("전체 문자 \(totalMessages)건 중")
                            .font(.subheadline)

                        Text("스팸 문자 \(blockedMessages)건을 차단했어요")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Spacer().frame(height: 1)

                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)

                                Circle()
                                    .trim(from: 0, to: CGFloat(Double(blockedMessages) / max(Double(totalMessages), 1.0)))
                                    .stroke(Color.red, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                                    .rotationEffect(.degrees(-90))

                                Text("\(Int(spamRate * 100))%")
                                    .font(.title2)
                                    .bold()
                            }
                            .frame(width: 120, height: 120)
                            Spacer()
                        }
                    }
                    .padding(30)
                    .background(Color.white)
                    .cornerRadius(12)

                    // 키워드 관리
                    VStack(spacing: 10) {
                        NavigationLinkCard(label: "블랙리스트 키워드", destination: BlacklistView())
                        NavigationLinkCard(label: "화이트리스트 키워드", destination: WhitelistView())
                    }

                    // 테스트용 버튼
                    Button("테스트용 메시지 차단 증가") {
                        let addedTotal   = Int.random(in: 1...10)
                        let addedBlocked = Int.random(in: 1...min(addedTotal, 10))
                        totalMessages   += addedTotal
                        blockedMessages += addedBlocked
                    }


                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ContentView()
}
