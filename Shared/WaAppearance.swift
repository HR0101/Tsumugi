//
//  WaAppearance.swift
//  Tsumugi
//
//  ナビゲーションバーとタブバーの見た目を整える.
//  SwiftUI からは書体を指定できないため, UIKit の Appearance を経由して明朝体を適用する.
//

import SwiftUI
import UIKit

enum WaAppearance {

  /// アプリ起動時に 1 度だけ呼ぶ.
  static func apply() {
    applyNavigationBar()
    applyTabBar()
  }

  private static func applyNavigationBar() {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(Palette.ground)
    // 影ではなく細い罫でバーの下端を示す.
    appearance.shadowColor = UIColor(Palette.rule)

    let ink = UIColor(Palette.ink)
    if let title = UIFont(name: "HiraMinProN-W6", size: 17) {
      appearance.titleTextAttributes = [.font: title, .foregroundColor: ink]
    } else {
      appearance.titleTextAttributes = [.foregroundColor: ink]
    }
    if let largeTitle = UIFont(name: "HiraMinProN-W6", size: 30) {
      appearance.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink]
    } else {
      appearance.largeTitleTextAttributes = [.foregroundColor: ink]
    }

    UINavigationBar.appearance().standardAppearance = appearance
    UINavigationBar.appearance().scrollEdgeAppearance = appearance
    UINavigationBar.appearance().compactAppearance = appearance
  }

  private static func applyTabBar() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(Palette.ground)
    appearance.shadowColor = UIColor(Palette.rule)

    let selected = UIColor(Palette.indigo)
    let normal = UIColor(Palette.inkMuted)

    for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
      layout.selected.iconColor = selected
      layout.normal.iconColor = normal
      if let font = UIFont(name: "HiraMinProN-W6", size: 10) {
        layout.selected.titleTextAttributes = [.font: font, .foregroundColor: selected]
        layout.normal.titleTextAttributes = [.font: font, .foregroundColor: normal]
      } else {
        layout.selected.titleTextAttributes = [.foregroundColor: selected]
        layout.normal.titleTextAttributes = [.foregroundColor: normal]
      }
    }

    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }
}
