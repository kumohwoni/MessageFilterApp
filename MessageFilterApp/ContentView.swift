//
//  ContentView.swift
//  MessageFilterApp
//
import SwiftUI

struct ContentView: View {
    @State private var localSpamFilterOn = true
    @State private var advancedSpamFilterOn = false

    @StateObject private var stats = StatsManager()
    @Environment(\.scenePhase) private var scenePhase

    var spamRate: Double {
        Double(stats.blockedMessages) / max(Double(stats.totalMessages), 1.0)
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

                        Text("전체 문자 \(stats.totalMessages)건 중")
                            .font(.subheadline)

                        Text("스팸 문자 \(stats.blockedMessages)건을 차단했어요")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Spacer().frame(height: 1)

                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)

                                Circle()
                                    .trim(from: 0, to: CGFloat(Double(stats.blockedMessages) / max(Double(stats.totalMessages), 1.0)))
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
                        stats.totalMessages   += addedTotal
                        stats.blockedMessages += addedBlocked
                    }
                    Button("UserDefaults 직접 증가") {
                        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")!
                        let before = defaults.integer(forKey: "totalReceivedCount")
                        defaults.set(before + 1, forKey: "totalReceivedCount")
                        defaults.synchronize()
                        stats.reload()
                    }



                }
                .padding()
            }
            // 1) pull-to-refresh
            .refreshable {
                stats.reload()  // UserDefaults에서 강제로 한 번 더 읽어오기
            }
            .navigationBarHidden(true)
        }
        .onAppear()
        {
            stats.reload()
        }
        // 2) 앱 포그라운드 진입 시 자동 갱신
        .onChange(of: scenePhase) {
            // 값이 바뀔 때마다 실행되므로, 직접 새 값을 읽습니다.
            if scenePhase == .active {
                stats.reload()
            }
        }

    }
}

final class StatsManager: ObservableObject {
    private let shared = UserDefaults(suiteName: "group.com.messagefilterapp.shared")!

    @Published var totalMessages: Int = {
        UserDefaults(suiteName: "group.com.messagefilterapp.shared")!.integer(forKey: "totalReceivedCount")
    }()
    @Published var blockedMessages: Int = {
        UserDefaults(suiteName: "group.com.messagefilterapp.shared")!.integer(forKey: "junkCount")
    }()

    init() {
        // 이후 실시간 갱신이 필요하면 reload()를 쓰거나 scenePhase/pull-to-refresh 로직만 남기면 됩니다.
    }

    func reload() {
        totalMessages   = shared.integer(forKey: "totalReceivedCount")
        blockedMessages = shared.integer(forKey: "junkCount")
    }
}

