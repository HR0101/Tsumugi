//
//  SearchView.swift
//  Tsumugi
//
//  仕様書 S-07 / LB-04 / LB-05: 検索結果画面.
//  キーワード検索（日本語形態素）とセマンティック検索（語の共起による近似）を統合して表示する.
//

import SwiftUI
import SwiftData

struct SearchView: View {

  @Query(sort: \Item.savedAt, order: .reverse) private var allItems: [Item]
  @Environment(IngestService.self) private var ingest

  @State private var query = ""
  @State private var scope: SearchScope = .all

  enum SearchScope: String, CaseIterable, Identifiable {
    case all
    case keyword
    case semantic

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .all: return "統合"
      case .keyword: return "キーワード"
      case .semantic: return "意味が近い"
      }
    }
  }

  /// 検索結果 1 件.
  private struct Hit: Identifiable {
    let item: Item
    let score: Double
    let isKeywordMatch: Bool
    /// 一致箇所の抜粋.
    let snippet: String?

    var id: UUID { item.id }
  }

  var body: some View {
    NavigationStack {
      Group {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
          suggestions
        } else if hits.isEmpty {
          EmptyStateView(
            symbolName: "magnifyingglass",
            title: "見つかりませんでした",
            message: "別のキーワードでお試しください. 本文・要約・メモ・タグを横断して検索しています."
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          resultList
        }
      }
      .background(Palette.canvas)
      .navigationTitle("検索")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "キーワードを入力")
      .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
      }
    }
  }

  // MARK: - 結果一覧

  private var resultList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Spacing.md) {
        Picker("検索範囲", selection: $scope) {
          ForEach(SearchScope.allCases) { value in
            Text(value.displayName).tag(value)
          }
        }
        .pickerStyle(.segmented)

        Text("\(hits.count) 件")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(hits) { hit in
          NavigationLink(value: hit.item) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
              HStack(alignment: .top) {
                Text(hit.item.title)
                  .font(.subheadline.weight(.semibold))
                  .multilineTextAlignment(.leading)
                  .lineLimit(2)
                Spacer()
                Image(systemName: hit.isKeywordMatch ? "textformat.abc" : "sparkles")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
                  .accessibilityLabel(hit.isKeywordMatch ? "キーワード一致" : "意味が近い")
              }

              ItemMetaLine(item: hit.item)

              if let snippet = hit.snippet {
                Text(snippet)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(3)
                  .multilineTextAlignment(.leading)
              }

              ItemBadgeRow(item: hit.item, isProcessing: ingest.inFlightItemIDs.contains(hit.item.id))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: Spacing.md)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
    }
  }

  private var suggestions: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        if !recentTagNames.isEmpty {
          VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("よく使うタグ").sectionTitleStyle()
            FlowLayout(spacing: Spacing.sm) {
              ForEach(recentTagNames, id: \.self) { name in
                Button {
                  query = name
                } label: {
                  Text("#\(name)")
                    .font(.caption)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Palette.cardBackground, in: Capsule())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text("検索のヒント").sectionTitleStyle()
          Label("タイトル・本文・要約・メモ・タグを横断して検索します.", systemImage: "doc.text.magnifyingglass")
          Label("「意味が近い」は語の共起から関連度を推定します. 完全一致しない記事も拾えます.", systemImage: "sparkles")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .padding(Spacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var recentTagNames: [String] {
    let names = allItems.flatMap { $0.tags.map(\.name) }
    let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
    return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(8).map(\.key)
  }

  // MARK: - 検索処理

  private var hits: [Hit] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    // 仕様書 LB-04: 日本語は形態素境界で分割してから照合する.
    let queryTerms = Set(TextAnalysis.words(in: trimmed).filter { $0.count >= 2 })

    var results: [Hit] = []
    for item in allItems {
      let isKeywordMatch = item.matches(query: trimmed)

      // 仕様書 LB-05 の近似: サーバ側の埋め込みベクトルの代わりに,
      // 語の重なり率で意味的な近さを推定する.
      // 本文全体をトークン化すると重くなるため, 見出し・要約・タグに絞る.
      let semanticScore = semanticSimilarity(queryTerms: queryTerms, corpus: item.searchHeadline)

      let score = (isKeywordMatch ? 1.0 : 0.0) + semanticScore
      guard score > 0.12 else { continue }

      switch scope {
      case .keyword where !isKeywordMatch: continue
      case .semantic where isKeywordMatch: continue
      default: break
      }

      results.append(
        Hit(
          item: item,
          score: score,
          isKeywordMatch: isKeywordMatch,
          snippet: snippet(for: trimmed, in: item.searchSnippetSource)
        )
      )
    }

    return results.sorted { $0.score > $1.score }
  }

  private func semanticSimilarity(queryTerms: Set<String>, corpus: String) -> Double {
    guard !queryTerms.isEmpty, !corpus.isEmpty else { return 0 }
    let corpusTerms = Set(TextAnalysis.words(in: corpus).filter { $0.count >= 2 })
    guard !corpusTerms.isEmpty else { return 0 }
    let shared = queryTerms.intersection(corpusTerms).count
    return Double(shared) / Double(queryTerms.count)
  }

  /// 一致箇所の前後を切り出す.
  private func snippet(for query: String, in corpus: String) -> String? {
    guard let range = corpus.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
      return String(corpus.prefix(120))
    }
    let start = corpus.index(range.lowerBound, offsetBy: -40, limitedBy: corpus.startIndex) ?? corpus.startIndex
    let end = corpus.index(range.upperBound, offsetBy: 80, limitedBy: corpus.endIndex) ?? corpus.endIndex
    return "…" + corpus[start..<end].replacingOccurrences(of: "\n", with: " ") + "…"
  }
}
