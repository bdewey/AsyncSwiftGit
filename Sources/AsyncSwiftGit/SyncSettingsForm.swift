// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import SwiftUI

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
public struct SyncSettingsForm: View {
  @Binding public var settings: GitConnectionSettings
  public var shouldShowValidIndicator = false

  public init(settings: Binding<GitConnectionSettings>, shouldShowValidIndicator: Bool = false) {
    self._settings = settings
    self.shouldShowValidIndicator = shouldShowValidIndicator
  }

  public var body: some View {
    Form {
      Picker("Connection", selection: $settings.connectionType.animation()) {
        Text("HTTPS").tag(GitConnectionSettings.AuthenticationType.usernamePassword)
        Text("SSH").tag(GitConnectionSettings.AuthenticationType.ssh)
      }.pickerStyle(.segmented)
      Section("Server") {
        TextField("URL", text: $settings.remoteURLString)
          .foregroundColor(settings.isRemoteURLValid ? .primary : .red)
          .disableAutocorrection(true)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .textContentType(.URL)
        #endif
        if settings.connectionType == .usernamePassword {
          TextField("Username", text: $settings.email)
            .disableAutocorrection(true)
          #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
          #endif
        }
        SecureField("Password", text: $settings.password).textContentType(.password)
        if settings.connectionType == .ssh {
          TextField("Public key", text: $settings.sshKeyPair.publicKey).sshKey()
        }
      }
      if settings.connectionType == .ssh {
        Section("Private key") {
          TextEditor(text: $settings.sshKeyPair.privateKey).sshKey()
        }
      }
      Toggle("Read Only", isOn: $settings.isReadOnly.animation())
      if !settings.isReadOnly {
        Section("Personal Information") {
          TextField("Email", text: $settings.email)
            .disableAutocorrection(true)
          #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
          #endif
          TextField("Name", text: $settings.username)
          #if os(iOS)
            .textInputAutocapitalization(.words)
            .textContentType(.name)
          #endif
        }
      }
      if shouldShowValidIndicator {
        Text(settings.isValid ? "Valid" : "Invalid")
          .foregroundColor(settings.isValid ? .secondary : .red)
          .font(.caption)
      }
    }
  }
}

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
struct SSHKeyModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(.body.monospaced())
      .disableAutocorrection(true)
    #if os(iOS)
      .textInputAutocapitalization(.never)
    #endif
  }
}

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
extension View {
  func sshKey() -> some View {
    modifier(SSHKeyModifier())
  }
}

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
struct DebugJournalRepositorySettingsView: View {
  @State private var settings = GitConnectionSettings()

  var body: some View {
    NavigationView {
      SyncSettingsForm(settings: $settings, shouldShowValidIndicator: true)
        .navigationTitle("Testing")
    }
  }
}

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
struct JournalRepositorySettingsView_Previews: PreviewProvider {
  static var previews: some View {
    DebugJournalRepositorySettingsView()
      .preferredColorScheme(.dark)
  }
}
