import Foundation
import SwiftUI

extension Binding {
    func withDefault<T>(_ defaultValue: T?) -> Binding<T?> where Value == T? {
        Binding<T?>(get: {
            self.wrappedValue ?? defaultValue
        }, set: { newValue in
            self.wrappedValue = newValue
        })
    }

    func withDefault<T>(_ defaultValue: T) -> Binding<T> where Value == T? {
        Binding<T>(get: {
            self.wrappedValue ?? defaultValue
        }, set: { newValue in
            self.wrappedValue = newValue
        })
    }
}
