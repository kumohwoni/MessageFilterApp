import SwiftUI

struct BlacklistView: View {
    @State private var newKeyword = ""
    @State private var keywords: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            // 입력창 + 버튼
            HStack {
                TextField("차단할 키워드 입력", text: $newKeyword)
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
                hideKeyboard() // 빈 공간 탭 시 키보드 닫힘
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
        .navigationTitle("블랙리스트 키워드")
        .onAppear(perform: loadKeywords) // 👈 여기가 핵심
    }

    func addKeyword() {
        guard !newKeyword.isEmpty else { return }
        keywords.append(newKeyword)
        newKeyword = ""
        saveKeywords()
    }

    func deleteKeyword(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
        saveKeywords()
    }

    func saveKeywords() {
        UserDefaults.standard.set(keywords, forKey: "blacklist")
    }

    func loadKeywords() {
        keywords = UserDefaults.standard.stringArray(forKey: "blacklist") ?? []
    }
}
