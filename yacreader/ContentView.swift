//
//  ContentView.swift
//  yacreader
//
//  Created by 欧君子 on 2026/3/17.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    var body: some View {
        LibraryHomeView(viewModel: viewModel, dependencies: dependencies)
    }
}
