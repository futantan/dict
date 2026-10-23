// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import CoreGraphics

/// The permissions Dict checks (architecture 3.8). Both are granted in System Settings →
/// Privacy & Security → Accessibility.
enum Permission: Sendable, Hashable, CaseIterable {
  /// Reads the selection, presses Copy menu items and replaces text.
  case accessibility
  /// Posts the targeted ⌘C and ⌘V.
  case postEvent
}

/// One reading of both permissions.
struct PermissionStatus: Sendable, Equatable {
  var accessibility: Bool
  var postEvent: Bool

  func isGranted(_ permission: Permission) -> Bool {
    switch permission {
    case .accessibility: accessibility
    case .postEvent: postEvent
    }
  }

  /// The permissions that are off, in `Permission.allCases` order.
  var missing: [Permission] { Permission.allCases.filter { !isGranted($0) } }

  /// The permissions that are on now but were off in `old`.
  func newlyGranted(since old: PermissionStatus) -> Set<Permission> {
    Set(Permission.allCases.filter { isGranted($0) && !old.isGranted($0) })
  }
}

/// Reads the permission state. Implementations must never prompt.
protocol PermissionChecker: Sendable {
  func status() -> PermissionStatus
}

/// The real checker. It uses only the preflight calls, which never show the system's
/// authorization alert; Dict explains permissions in its own panel (architecture 11.1).
struct SystemPermissionChecker: PermissionChecker {
  func status() -> PermissionStatus {
    PermissionStatus(accessibility: AXIsProcessTrusted(), postEvent: CGPreflightPostEventAccess())
  }
}

/// What the panel explains when a permission blocks the user.
enum PermissionIssue: Sendable, Hashable, CaseIterable {
  case missing(Permission)
  /// System Settings shows Dict as allowed, but the grant belongs to an earlier signature,
  /// so accessibility calls still fail (architecture 3.4, 3.8).
  case staleAccessibility

  static let allCases: [PermissionIssue] = [
    .missing(.accessibility), .missing(.postEvent), .staleAccessibility,
  ]

  /// The issue behind a capture failure, judged against a fresh `status`; nil when the
  /// failure is not about permissions or the permission has been granted since.
  init?(_ failure: CaptureFailure, status: PermissionStatus) {
    switch failure {
    case .noAccessibilityPermission:
      // Capture also reports this when the API is disabled although the process is trusted.
      self = status.accessibility ? .staleAccessibility : .missing(.accessibility)
    case .noPostEventPermission:
      self.init(postEventWith: status)
    case .secureField, .secureInput, .clipboardDenied, .ownApp, .nothingSelected, .unreadable:
      return nil
    }
  }

  /// The issue behind a replace failure; see the capture variant.
  init?(_ reason: FailReason, status: PermissionStatus) {
    switch reason {
    case .noPostEventPermission: self.init(postEventWith: status)
    case .pasteNotApplied, .clipboardDenied: return nil
    }
  }

  /// Posting needs both permissions (architecture 3.6), and accessibility comes first.
  private init?(postEventWith status: PermissionStatus) {
    guard let first = status.missing.first else { return nil }
    self = .missing(first)
  }
}
