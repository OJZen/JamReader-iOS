import Foundation

struct RemoteServerProfileValidator {
    func validate(_ profile: RemoteServerProfile) -> [RemoteServerValidationIssue] {
        var issues: [RemoteServerValidationIssue] = []

        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "A display name is required for the remote server."
                )
            )
        }

        if profile.normalizedHost.isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Host cannot be empty."
                )
            )
        }

        if profile.port <= 0 || profile.port > 65535 {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Port must be between 1 and 65535."
                )
            )
        }

        switch profile.providerKind {
        case .smb:
            if profile.normalizedShareName.isEmpty {
                issues.append(
                    RemoteServerValidationIssue(
                        severity: .error,
                        message: "Share name cannot be empty."
                    )
                )
            }
        case .webdav:
            if profile.webDAVBaseURL == nil {
                issues.append(
                    RemoteServerValidationIssue(
                        severity: .error,
                        message: "Enter a valid WebDAV host or URL."
                    )
                )
            }
        }

        if profile.authenticationMode.requiresUsername
            && profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Username is required for this authentication mode."
                )
            )
        }

        if profile.authenticationMode.requiresPassword && profile.passwordReferenceKey == nil {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "A saved password is required for this remote server."
                )
            )
        }

        return issues
    }
}
