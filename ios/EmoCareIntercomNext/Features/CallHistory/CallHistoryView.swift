import SwiftUI

struct CallHistoryView: View {
    @StateObject private var viewModel = CallHistoryViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: CallHistoryFilter = .all
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.filteredCalls.isEmpty {
                LoadingStateView()
            } else if viewModel.filteredCalls.isEmpty {
                EmptyStateView()
            } else {
                List {
                    StatisticsSummarySection()
                    
                    ForEach(groupedCalls, id: \.key) { section in
                        Section(header: Text(section.key)) {
                            ForEach(section.value) { call in
                                CallRowView(call: call)
                                    .contextMenu {
                                        CallContextMenu(call: call)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refreshCallHistory()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .navigationTitle("通話履歴")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "通話を検索")
        .onChange(of: searchText) { newValue in
            viewModel.searchCalls(query: newValue)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(CallHistoryFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                            viewModel.applyFilter(filter)
                        } label: {
                            if selectedFilter == filter {
                                Label(filter.displayName, systemImage: "checkmark")
                            } else {
                                Text(filter.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task {
            await viewModel.loadCallHistory()
            viewModel.applyFilter(selectedFilter)
        }
        .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Statistics Summary
    @ViewBuilder
    private func StatisticsSummarySection() -> some View {
        if !viewModel.isLoading {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    StatisticCardView(
                        title: "今日",
                        value: "\(viewModel.statistics.todayCalls)",
                        subtitle: "回",
                        color: .blue
                    )
                    
                    StatisticCardView(
                        title: "今週",
                        value: "\(viewModel.statistics.weekCalls)",
                        subtitle: "回",
                        color: .green
                    )
                    
                    StatisticCardView(
                        title: "平均時間",
                        value: viewModel.statistics.averageDurationString,
                        subtitle: "",
                        color: .orange
                    )
                    
                    StatisticCardView(
                        title: "緊急通話",
                        value: "\(viewModel.statistics.emergencyCalls)",
                        subtitle: "回",
                        color: .red
                    )
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)
        }
    }
    
    // MARK: - Loading State
    @ViewBuilder
    private func LoadingStateView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("通話履歴を読み込み中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    @ViewBuilder
    private func EmptyStateView() -> some View {
        VStack(spacing: 24) {
            Image(systemName: "phone.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("通話履歴がありません")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if searchText.isEmpty && selectedFilter == .all {
                    Text("まだ通話をしていません")
                        .foregroundColor(.secondary)
                } else {
                    Text("条件に一致する通話が見つかりません")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var groupedCalls: [(key: String, value: [CallRecord])] {
        Dictionary(grouping: viewModel.filteredCalls) { call in
            formatDateSection(call.startTime)
        }
        .sorted { $0.key > $1.key }
        .map { (key: $0.key, value: $0.value.sorted { $0.startTime > $1.startTime }) }
    }
    
    // MARK: - Private Methods
    
    private func formatDateSection(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "今日"
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "今週"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年MM月dd日"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Statistic Card View
struct StatisticCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 80)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: color.opacity(0.1), radius: 4)
    }
}

// MARK: - Call Row View
struct CallRowView: View {
    let call: CallRecord
    @StateObject private var channelsViewModel = ChannelsViewModel()
    @State private var channelName = "不明なチャンネル"
    
    var body: some View {
        HStack(spacing: 16) {
            // 通話タイプアイコン
            CallTypeIconView(call: call)
            
            // 通話情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channelName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if call.isEmergency {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Text(formatTime(call.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(formatDuration(call.duration))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    CallStatusBadge(call: call)
                }
            }
        }
        .padding(.vertical, 8)
        .task {
            await loadChannelInfo()
        }
    }
    
    private func loadChannelInfo() async {
        if let channel = channelsViewModel.getChannelByID(call.channelId) {
            await MainActor.run {
                channelName = channel.name
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: Int) -> String {
        let minutes = duration / 60
        let seconds = duration % 60
        
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
}

// MARK: - Call Type Icon View
struct CallTypeIconView: View {
    let call: CallRecord
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 40, height: 40)
            
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(foregroundColor)
        }
    }
    
    private var backgroundColor: Color {
        if call.isEmergency {
            return Color.red.opacity(0.1)
        } else {
            switch call.callType {
            case .voip: return Color.blue.opacity(0.1)
            case .ptt: return Color.green.opacity(0.1)
            }
        }
    }
    
    private var foregroundColor: Color {
        if call.isEmergency {
            return .red
        } else {
            switch call.callType {
            case .voip: return .blue
            case .ptt: return .green
            }
        }
    }
    
    private var iconName: String {
        if call.isEmergency {
            return "exclamationmark.triangle.fill"
        } else {
            switch call.callType {
            case .voip: return "phone.fill"
            case .ptt: return "mic.fill"
            }
        }
    }
}

// MARK: - Call Status Badge
struct CallStatusBadge: View {
    let call: CallRecord
    
    var body: some View {
        Text(statusText)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }
    
    private var statusText: String {
        if call.endTime != nil {
            return "完了"
        } else {
            return "失敗"
        }
    }
    
    private var statusColor: Color {
        if call.endTime != nil {
            return .green
        } else {
            return .red
        }
    }
}

// MARK: - Call Context Menu
struct CallContextMenu: View {
    let call: CallRecord
    
    var body: some View {
        Button {
            // 詳細表示
        } label: {
            Label("詳細を表示", systemImage: "info.circle")
        }
        
        Button {
            // 再通話
        } label: {
            Label("再通話", systemImage: "phone")
        }
        
        if call.callType == .voip {
            Button {
                // 通話を録画として保存（将来機能）
            } label: {
                Label("記録を保存", systemImage: "square.and.arrow.down")
            }
        }
    }
}

// MARK: - Call History Filter
enum CallHistoryFilter: String, CaseIterable {
    case all = "all"
    case voip = "voip"
    case ptt = "ptt"
    case emergency = "emergency"
    case today = "today"
    case week = "week"
    
    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .voip: return "音声通話"
        case .ptt: return "PTT"
        case .emergency: return "緊急"
        case .today: return "今日"
        case .week: return "今週"
        }
    }
}

#Preview {
    NavigationView {
        CallHistoryView()
    }
    .environmentObject(AuthenticationManager())
}
