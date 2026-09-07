import SwiftUI

struct AnalyticsInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
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
                        // Params Grid
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(selected.params.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(key)
                                            .foregroundColor(theme.current.accent)
                                            .frame(width: 82, alignment: .leading)
                                        Text(value)
                                            .foregroundColor(theme.current.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.system(size: 10.5, design: .monospaced))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        .background(theme.current.bgPanel)
                        
                        Divider().background(theme.current.border)
                        
                        // Raw Log
                        ScrollView {
                            Text(selected.rawLog)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(theme.current.textSecondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        .background(theme.current.bgPanel)
                    }
                    .frame(minHeight: 150)
                } else {
                    VStack {
                        Text("Selecione um evento para ver os detalhes")
                            .font(.system(size: 12))
                            .foregroundColor(theme.current.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.current.bgPanel)
                }
            }
        }
        .background(theme.current.bgWindow)
    }
}
