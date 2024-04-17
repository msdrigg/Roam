//
//  MessagingView.swift
//  Roam
//
//  Created by Scott Driggers on 4/16/24.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog
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
        } else if let error = error {
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

public func refreshMessages(modelContainer: ModelContainer, latestMessageId: String?, viewed: Bool) async -> Int {
    let modelContext = ModelContext(modelContainer)
    do {
        var count = 0
        do {
            let newMessages = try await getMessages(after: latestMessageId)
            
            for message in newMessages {
                message.viewed = viewed
                modelContext.insert(message)
            }
            count = newMessages.count
        } catch {
            logger.error("Error getting latest messages \(error)")
        }
        
        logger.info("Starting delete")
        let foundModels = try modelContext.fetch(FetchDescriptor(
            predicate: #Predicate<Message> { model in
            !model.fetchedBackend
        }))
        for model in foundModels {
            modelContext.delete(model)
        }
        logger.info("Ending delete")
        
        if viewed == true {
            let unviewedMessagesDescriptor = FetchDescriptor<Message>(predicate: #Predicate {
                !$0.viewed
            })
            let unviewedMessages = try modelContext.fetch<Message>(unviewedMessagesDescriptor)
            for message in unviewedMessages {
                message.viewed = true
            }
        }
        
        try modelContext.save()
        
        return count
    } catch {
        logger.error("Error refreshing messages \(error)")
        return 0
    }
}


enum MessagingDestination {
    case Global
}

struct MessageView: View {
    @State private var messageText = ""
    @Query(sort: \Message.id) private var baseMessages: [Message]
    @State private var textEditorHeight : CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @AppStorage("hasSentFirstMessage") private var hasSentFirstMessage: Bool = false
    @Environment(\.colorScheme) var colorScheme

    @Environment(\.modelContext) private var modelContext
    
    var messages: [Message] {
        return ([Message(id: "start", message: "Hi, I'm Scott. I make Roam. What's on your mind? I'll do my best to respond to these messages as quick as I can.", author: .support, fetchedBackend: false)] + baseMessages).filter{!$0.message.isEmpty}
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
                                        Text(message.message)
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
                                        Text(message.message)
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
                    }
                    .defaultScrollAnchor(.bottom)
                    .padding(.vertical, 12)
                    .onChange(of: messages.count) { old, new in
                        if let id = messages.last?.persistentModelID {
                            print("Scrolling here \(messages.last?.id ?? "")")
                            withAnimation {
                                scrollValue.scrollTo(id, anchor: .bottom)
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
                        .lineLimit(1...8)
                        .textFieldStyle(PlainTextFieldStyle())
                        .fixedSize(horizontal: false, vertical: true)
                        .background(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary, lineWidth: 2).background(Color.clear))
                        .scrollIndicators(.hidden)

#if os(macOS)
                    EmojiPicker().padding(.bottom, 2)
#else
                    Button(action: sendTypedMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .foregroundColor(Color.accentColor)
                    }
#endif
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear {
                UNUserNotificationCenter.current().setBadgeCount(0)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
        .task(id: refreshResetId) {
            refreshInterval = 10
            await handleRefresh()
        }  
        .frame(minHeight: 200)
        .frame(width: 400)
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
            let latestMessageId = messages.last{$0.fetchedBackend == true}?.id
            
            let result = await refreshMessages(modelContainer: modelContext.container, latestMessageId: latestMessageId, viewed: true)
            logger.info("Got results \(result)")
            if result > 0 {
                refreshInterval = 10
            } else {
                if refreshInterval < 60 {
                    refreshInterval = min(refreshInterval * 2, 60)
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
        Task {
            do {
                try await sendMessage(message: messageCopy, apnsToken: nil)
                if await refreshMessages(modelContainer: modelContext.container, latestMessageId: messages.last{$0.fetchedBackend}?.id, viewed: true) > 0 {
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
        .modelContainer(devicePreviewContainer)
}
