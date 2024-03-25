#if !os(macOS)
import Foundation
import SwiftUI
import os.log

@available(iOS, introduced: 17.0)
struct KeyboardEntry: View {
    @Binding var str: String
    @Binding var showing: Bool
    @State var strSent: String = ""
    @FocusState private var keyboardFocused: Bool
    let onKeyPress:  (_ press: KeyEquivalent) -> Void
    let leaving: Bool
    
    var body: some View {
        TextFieldContainer("Enter some text...", text: $str, onDelete: {
            onKeyPress(.delete)
        }, onDone: {
            withAnimation {
                keyboardFocused = false
                showing = false
            }
        })
        #if !os(tvOS)
        .textSelection(.disabled)
        #endif
        .focused($keyboardFocused)
        .font(.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary))
        .frame(height: 60)
        #if !os(tvOS)
        .task {
            let listener = KeyboardListener()
            if let events = listener.events {
                for await _ in events {
                    DispatchQueue.main.async {
                        withAnimation {
                            keyboardFocused = false
                            showing = false
                        }
                    }
                }
            }
        }
        #endif
        .onChange(of: str) {
            if str.count > strSent.count {
                if let char = str.unicodeScalars.last {
                    onKeyPress(KeyEquivalent(Character(char)))
                }
            }
            
            strSent = str
        }
        .onChange(of: leaving) {
            if leaving {
                withAnimation {
                    keyboardFocused = false
                    showing = false
                }
            }
        }
        .onAppear {
            keyboardFocused = true
            str = ""
            strSent = ""
        }
        
    }
}

class EndOnlyTextField: UITextField {
    var didDelete: (() -> Void)? = nil
    
    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        let beginning = self.beginningOfDocument
        let end = self.position(from: beginning, offset: self.text?.count ?? 0)
        return end
    }
    
    override func deleteBackward() {
        self.didDelete?()
        super.deleteBackward()
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Disable cut, copy, paste, select, selectAll
        if action == #selector(cut(_:)) || action == #selector(copy(_:)) || action == #selector(paste(_:)) || action == #selector(select(_:)) || action == #selector(selectAll(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        // Return empty array to prevent selection
        return []
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        // Force the caret to the end of the text
        guard let endPosition = self.position(from: self.endOfDocument, offset: 0) else {
            return super.caretRect(for: position)
        }
        return super.caretRect(for: endPosition)
    }
}

struct TextFieldContainer: UIViewRepresentable {
    private var placeholder : String
    private var text : Binding<String>
    private var onDelete: () -> Void
    private var onDone: () -> Void
    
    init(_ placeholder:String, text:Binding<String>, onDelete: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.placeholder = placeholder
        self.text = text
        self.onDelete = onDelete
        self.onDone = onDone
    }
    
    func makeCoordinator() -> TextFieldContainer.Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: UIViewRepresentableContext<TextFieldContainer>) -> UITextField {
        
        let innertTextField = EndOnlyTextField(frame: .zero)
        innertTextField.placeholder = placeholder
        innertTextField.text = text.wrappedValue
        innertTextField.delegate = context.coordinator
        innertTextField.didDelete = onDelete
        
        context.coordinator.setup(innertTextField)
        
        return innertTextField
    }
    
    func updateUIView(_ uiView: UITextField, context: UIViewRepresentableContext<TextFieldContainer>) {
        uiView.text = self.text.wrappedValue
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TextFieldContainer
        
        init(_ textFieldContainer: TextFieldContainer) {
            self.parent = textFieldContainer
        }
        
        func setup(_ textField:UITextField) {
            textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
            textField.becomeFirstResponder()
        }
        
        #if !os(iOS)
        @objc func textFieldDidEndEditing(_ textField: UITextField) {
            self.parent.onDone()
        }
        #endif
        @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            self.parent.onDone()
            return true
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            self.parent.text.wrappedValue = textField.text ?? ""
            
            let newPosition = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
        }
    }
}

#if !os(tvOS)
class KeyboardListener {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: KeyboardListener.self)
    )
    
    var keyboardHideNotifier: (() -> Void)? = nil
    
    @objc func handleHideKeyboard(notification: Notification) {
        self.keyboardHideNotifier?()
    }
    
    func startListening() throws {
        Self.logger.info("Starting keyboard observations")
        // Get the default notification center instance.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideKeyboard),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    func stopListening() {
        Self.logger.info("Stoping keyboard observations")
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    var events: AsyncStream<Bool>? {
        return AsyncStream { continuation in
            do {
                try startListening()
                self.keyboardHideNotifier = {
                    continuation.yield(true)
                }
                continuation.onTermination = { @Sendable _ in
                    self.stopListening()
                }
            } catch {}
        }
    }
}
#endif
#endif
