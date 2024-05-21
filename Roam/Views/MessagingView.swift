//
//  MessagingView.swift
//  Roam
//
//  Created by Scott Driggers on 4/16/24.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "MessagingView"
)

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
            logger.info("Notification permission granted.")
            getNotificationSettings()
        } else if let error {
            logger.error("Notification permission denied with error: \(error.localizedDescription)")
        }
    }
}

func getNotificationSettings() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else { return }
        DispatchQueue.main.async {
            #if os(macOS)
                logger.info("Registering for remote notifications")
                NSApplication.shared.registerForRemoteNotifications()
            #elseif !os(watchOS)
                UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }
}

struct MessageView: View {
    @State private var messageText = ""
    @Query(sort: \Message.id) private var baseMessages: [Message]
    @State private var textEditorHeight: CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @AppStorage("hasSentFirstMessage") private var hasSentFirstMessage: Bool = false
    @Environment(\.colorScheme) var colorScheme

    @Environment(\.modelContext) private var modelContext
    @Environment(\.createDataHandler) private var createDataHandler

    var messages: [Message] {
        ([Message(
            id: "start",
            message: "Hi, I'm Scott. I make Roam. What's on your mind? I'll do my best to respond to these messages as quick as I can.",
            author: .support,
            fetchedBackend: false
        )] + baseMessages).filter { !$0.message.isEmpty }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                ScrollViewReader { scrollValue in
                    ScrollView {
                        LazyVStack {
                            ForEach(messages, id: \.persistentModelID) { message in
                                HStack {
                                    if message.author == .me {
                                        Spacer()
                                        LinkedText(message.message)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(Color.accentColor.opacity(0.5))
                                            .foregroundStyle(
                                                colorScheme == .dark ? Color.white : Color.black
                                            )
                                            .cornerRadius(15)
                                            .frame(maxWidth: geometry.size.width * 2 / 3, alignment: .trailing)
                                            .padding(.trailing, 10)
                                    } else {
                                        LinkedText(message.message)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(Color.gray.opacity(0.5))
                                            .cornerRadius(15)
                                            .frame(maxWidth: geometry.size.width * 2 / 3, alignment: .leading)
                                            .padding(.leading, 10)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    #if !os(visionOS)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .textSelection(.enabled)
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.persistentModelID {
                            withAnimation {
                                scrollValue.scrollTo(id)
                            }
                        }
                    }
                    .onAppear {
                        if let id = messages.last?.persistentModelID {
                            withAnimation {
                                scrollValue.scrollTo(id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: $messageText, axis: .vertical)
                        .onSubmit {
                            sendTypedMessage()
                        }
                        .font(.system(.body))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .lineLimit(1 ... 8)
                        .textFieldStyle(PlainTextFieldStyle())
                        .background(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary, lineWidth: 2)
                            .background(Color.clear))
                        .scrollIndicators(.hidden)
                    #if os(visionOS)
                        .padding(.bottom, 6)
                    #endif

                    #if os(macOS)
                        EmojiPicker().padding(.bottom, 2)
                    #else
                        Button(action: sendTypedMessage) {
                            Label("Send", systemImage: "arrow.up")
                        }
                        .buttonBorderShape(.circle)
                        .buttonStyle(.borderedProminent)
                        .labelStyle(.iconOnly)

                    #endif
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .onAppear {
                UNUserNotificationCenter.current().setBadgeCount(0)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
        .navigationTitle("Messages")
        .task(id: refreshResetId) {
            refreshInterval = 10
            await handleRefresh()
        }
        #if os(macOS)
        .frame(minHeight: 200)
        .frame(width: 400)
        #endif
        .navigationTitle("Messages")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func handleRefresh() async {
        while true {
            if Task.isCancelled {
                return
            }
            logger.info("Refreshing messages")
            try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
            let latestMessageId = messages.last { $0.fetchedBackend == true }?.id

            if latestMessageId != nil {
                let createDataHandler = self.createDataHandler;
                let result = await Task.detached {
                    return await createDataHandler()?.refreshMessages(
                        latestMessageId: latestMessageId,
                        viewed: true
                    ) ?? 0
                }.value
                logger.info("Got results \(result)")

                if result > 0 {
                    refreshInterval = 10
                } else {
                    if refreshInterval < 60 {
                        refreshInterval = min(refreshInterval * 2, 60)
                    }
                }
            }

            logger.info("Sleeping for \(refreshInterval)s")
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            logger.info("Done sleeping")
        }
    }

    func sendTypedMessage() {
        logger.info("Sending message \"\(messageText)\"")
        let messageCopy = messageText
        let createDataHandler = self.createDataHandler;
        let latestMessageId = messages.last { $0.fetchedBackend == true }?.id;
        Task {
            do {
                try await Task.detached {
                    try await sendMessage(message: messageCopy, apnsToken: nil)
                }.value
                
                let result = await Task.detached {
                    return await createDataHandler()?.refreshMessages(
                        latestMessageId: latestMessageId,
                        viewed: true
                    ) ?? 0
                }.value
                
                if result > 0 {
                    refreshResetId = UUID()
                }
            } catch {
                logger.error("Error sending message \(error)")
            }
        }
        if !hasSentFirstMessage {
            // Request notification permissions on first message
            requestNotificationPermission()
        }

        messageText = ""
    }
}

#if os(macOS)
    import AppKit

    struct EmojiPicker: View {
        var body: some View {
            Button(action: {
                NSApp.orderFrontCharacterPalette(nil)
            }) {
                Image(systemName: "face.smiling")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

#endif

#Preview("Message View") {
    MessageView()
        .modelContainer(previewContainer)
}
