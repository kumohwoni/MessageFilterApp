//
//  NavigationLinkCard.swift
//  MessageFilterApp
//
import SwiftUI

struct NavigationLinkCard<Destination: View>: View {
    let label: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(10)
        }
    }
}
