import AppKit
import SwiftUI

struct AnalyticsInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    @State private var copiedParams = false
    @State private var copiedRaw = false
    
    var body: some View {
        VStack(spacing: 0) {
            AnalyticsToolbar()
            
            VSplitView {
                // Table
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 8) {
                        Text("HORA").frame(width: 80, alignment: .leading)
                        Text("EVENTO").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PARAMS").frame(width: 80, alignment: .leading)
                        Text("ORIGEM").frame(width: 80, alignment: .leading)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.current.textLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.current.bgSubtle)
                    
                    Divider().background(theme.current.borderSubtle)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.filteredAnalyticsEvents) { event in
                                let isSelected = appState.selectedAnalyticsEvent?.id == event.id
                                
                                HStack(spacing: 8) {
                                    Text(event.timeStr)
                                        .frame(width: 80, alignment: .leading)
                                    
                                    Text(event.eventName)
                                        .foregroundColor(theme.current.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text("\(event.paramCount)")
                                        .frame(width: 80, alignment: .leading)
                                    
                                    Text(event.tag)
                                        .frame(width: 80, alignment: .leading)
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isSelected ? theme.current.textPrimary : theme.current.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? theme.current.selectionBg : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedAnalyticsEvent = event
                                }
                                
                                Divider().background(theme.current.borderSubtle)
                            }
                        }
                    }
                }
                .frame(minHeight: 150)
                .background(theme.current.bgContent)
                
                // Detail Panel
                if let selected = appState.selectedAnalyticsEvent {
                    HStack(spacing: 0) {
                        // Params Panel
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                HStack(spacing: 6) {
                                    Text("Parâmetros")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(theme.current.textPrimary)
                                    
                                    Text("\(selected.params.count)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.current.accent.opacity(0.15))
                                        .foregroundColor(theme.current.accent)
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    copyText(
                                        selected.params.sorted(by: { $0.key < $1.key })
                                            .map { "\($0.key): \($0.value)" }
                                            .joined(separator: "\n"),
                                        isRaw: false
                                    )
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedParams ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text(copiedParams ? "Copiado" : "Copiar")
                                            .font(.system(size: 10.5, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(theme.current.bgControlTrack)
                                    .cornerRadius(5)
                                    .foregroundColor(copiedParams ? theme.current.success : theme.current.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copiar parâmetros")
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(theme.current.bgSubtle)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(theme.current.borderSubtle),
                                alignment: .bottom
                            )
                            
                            // Params list
                            ScrollView {
                                if selected.params.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "tag.slash")
                                            .font(.system(size: 24))
                                            .foregroundColor(theme.current.textTertiary.opacity(0.6))
                                        Text("Sem parâmetros no evento")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(theme.current.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 120)
                                    .padding()
                                } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(selected.params.sorted(by: { $0.key < $1.key }).enumerated()), id: \.element.key) { index, item in
                                            HStack(alignment: .top, spacing: 10) {
                                                Text(item.key)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(theme.current.accent)
                                                    .frame(width: 130, alignment: .leading)
                                                
                                                Text(item.value)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(theme.current.textPrimary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(index % 2 == 1 ? theme.current.bgContent.opacity(0.4) : Color.clear)
                                            
                                            Divider().background(theme.current.borderSubtle.opacity(0.5))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(theme.current.bgPanel)
                        
                        Divider().background(theme.current.border)
                        
                        // Raw Log Panel
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                HStack(spacing: 6) {
                                    Text("Log Bruto")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(theme.current.textPrimary)
                                    
                                    Text(selected.tag)
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.current.bgControlTrack)
                                        .foregroundColor(theme.current.textSecondary)
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    copyText(selected.rawLog, isRaw: true)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedRaw ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text(copiedRaw ? "Copiado" : "Copiar")
                                            .font(.system(size: 10.5, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(theme.current.bgControlTrack)
                                    .cornerRadius(5)
                                    .foregroundColor(copiedRaw ? theme.current.success : theme.current.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copiar log bruto")
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(theme.current.bgSubtle)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(theme.current.borderSubtle),
                                alignment: .bottom
                            )
                            
                            // Raw log content
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selected.rawLog)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(theme.current.textPrimary)
                                        .textSelection(.enabled)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(theme.current.bgContent)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(theme.current.borderSubtle, lineWidth: 1)
                                )
                                .padding(12)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(theme.current.bgPanel)
                    }
                    .frame(minHeight: 180)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 26))
                            .foregroundColor(theme.current.textTertiary.opacity(0.5))
                        
                        Text("Selecione um evento para ver os detalhes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.current.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.current.bgPanel)
                }
            }
        }
        .background(theme.current.bgWindow)
    }
    
    private func copyText(_ text: String, isRaw: Bool) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            if isRaw {
                copiedRaw = true
            } else {
                copiedParams = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if isRaw {
                copiedRaw = false
            } else {
                copiedParams = false
            }
        }
    }
}
