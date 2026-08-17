//
//  PermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Window dimensions for the permissions window.
enum PermissionsWindowMetrics {
    static let width: CGFloat = 608
    static let height: CGFloat = 480
}

/// The permissions screen: shown on first launch, and again whenever
/// permissions are missing on a later launch.
struct PermissionsView: View {
    @Environment(AppPermissions.self) private var permissions

    var onContinue: () -> Void

    /// Shows a Quit button beside Continue when non-nil.
    ///
    /// The window hides its close, minimize and zoom buttons, and Continue
    /// stays disabled until both permissions are granted, so without this
    /// there is no way out for a user who does not want to grant them.
    var onQuit: (() -> Void)?

    @State private var appeared = false

    private var allGranted: Bool {
        permissions.permissionsState == .hasAll
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("権限を許可")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    Text("あと少しです。\(Constants.displayName) がメニューバーを管理するには、以下の権限が必要です。")
                    Text("データはあなたの Mac から出ません。収集も共有も一切行いません。")
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            HStack(alignment: .top, spacing: 14) {
                ForEach(permissions.allPermissions) { permission in
                    PermissionCard(permission: permission)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if let onQuit {
                        Button {
                            onQuit()
                        } label: {
                            Text("終了")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(.glass)
                    }

                    Button {
                        onContinue()
                    } label: {
                        Text("続ける")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!allGranted)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }
}

private struct PermissionCard: View {
    let permission: Permission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: permission.iconName)
                    .foregroundStyle(permission.iconColor)

                Text(permission.title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(permission.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 3))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 5)

                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if permission.hasPermission {
                Label("権限が許可されました", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            } else {
                Button {
                    permission.performRequest()
                } label: {
                    Text("権限を許可")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeOut(duration: 0.3), value: permission.hasPermission)
    }
}
