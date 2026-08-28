//
//  FilterSheet.swift
//  Tsumugi
//
//  仕様書 LB-02 / LB-03: フィルタとソートの設定シート.
//

import SwiftUI
import SwiftData

struct FilterSheet: View {
  @Bindable var filter: LibraryFilter
  @Query(sort: \Tag.name) private var tags: [Tag]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("読了状態") {
          Picker("読了状態", selection: $filter.readState) {
            ForEach(ReadStateFilter.allCases) { state in
              Text(state.displayName).tag(state)
            }
          }
          .pickerStyle(.segmented)

          Toggle("お気に入りのみ", isOn: $filter.favoritesOnly)
        }

        Section {
          ForEach(CredibilityBand.allCases, id: \.self) { band in
            toggleRow(
              isOn: filter.credibilityBands.contains(band),
              symbolName: band.symbolName,
              color: Palette.color(for: band),
              title: band.displayName
            ) {
              toggle(band, in: &filter.credibilityBands)
            }
          }
        } header: {
          Text("信頼度")
        } footer: {
          Text("未診断の記事はこの絞り込みから除外されます.")
        }

        Section("情報の新しさ") {
          ForEach([StalenessLabel.current, .aging, .stale, .obsolete, .timeless, .unknown], id: \.self) { label in
            toggleRow(
              isOn: filter.stalenessLabels.contains(label),
              symbolName: label.symbolName,
              color: Palette.color(for: label),
              title: label.displayName
            ) {
              toggle(label, in: &filter.stalenessLabels)
            }
          }
        }

        if !tags.isEmpty {
          Section("タグ") {
            ForEach(tags) { tag in
              toggleRow(
                isOn: filter.selectedTagNames.contains(tag.name),
                symbolName: tag.source == .ai ? "sparkles" : "number",
                color: .secondary,
                title: "\(tag.name)（\(tag.itemCount)）"
              ) {
                toggle(tag.name, in: &filter.selectedTagNames)
              }
            }
          }
        }

        Section("保存期間") {
          Picker("保存期間", selection: $filter.period) {
            ForEach(SavedPeriodFilter.allCases) { period in
              Text(period.displayName).tag(period)
            }
          }
        }

        Section("並び順") {
          Picker("並び順", selection: $filter.sort) {
            ForEach(LibrarySort.allCases) { sort in
              Label(sort.displayName, systemImage: sort.symbolName).tag(sort)
            }
          }
          Toggle("昇順にする", isOn: $filter.isAscending)
        }
      }
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
      .navigationTitle("絞り込み")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("条件をクリア") { filter.reset() }
            .disabled(!filter.isActive)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
  }

  private func toggleRow(
    isOn: Bool,
    symbolName: String,
    color: Color,
    title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: symbolName)
          .foregroundStyle(color)
          .frame(width: 22)
        Text(title)
          .foregroundStyle(Palette.ink)
        Spacer()
        if isOn {
          Image(systemName: "checkmark")
            .foregroundStyle(Palette.indigo)
        }
      }
    }
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }

  private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
    if set.contains(value) { set.remove(value) } else { set.insert(value) }
  }
}
