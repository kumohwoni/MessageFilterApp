import SwiftUI

struct WhitelistView: View {
    @State private var newKeyword = ""
    @State private var keywords: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            // 입력창 + 버튼
            HStack {
                TextField("허용할 키워드 입력", text: $newKeyword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {
                    addKeyword()
                    hideKeyboard()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
            .padding()
            .onTapGesture {
                hideKeyboard()
            }

            // 리스트
            List {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                }
                .onDelete(perform: deleteKeyword)
            }

            Spacer()
        }
        .navigationTitle("화이트리스트 키워드")
        .onAppear(perform: loadKeywords)
    }

    func addKeyword() {
        guard !newKeyword.isEmpty else { return }
        keywords.append(newKeyword)
        newKeyword = ""
        saveKeywords()
        loadKeywords()
    }

    func deleteKeyword(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
        saveKeywords()
        loadKeywords()
    }

    func saveKeywords() {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        defaults?.set(keywords, forKey: "whitelist")
    }

    func loadKeywords() {
        let defaults = UserDefaults(suiteName: "group.com.messagefilterapp.shared")
        keywords = defaults?.stringArray(forKey: "whitelist") ?? []
    }

}
