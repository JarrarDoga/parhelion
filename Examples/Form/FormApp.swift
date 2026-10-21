import SwiftUI

@main
struct FormApp: App {
    var body: some Scene {
        WindowGroup {
            SignUpView()
        }
    }
}

struct SignUpView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign up")
            TextField("Name", text: $name)
                .padding(10)
                .background(.gray.opacity(0.15))
            TextField("Email", text: $email)
                .padding(10)
                .background(.gray.opacity(0.15))
            Button(action: { submitted = true }) {
                Text("Submit")
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(.blue)
            }
            if submitted {
                Text("Thanks, \(name)!")
            }
        }
        .padding(24)
    }
}
