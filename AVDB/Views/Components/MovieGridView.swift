//
//  MovieGridView.swift
//  AVDB
//
//  通用的影片网格视图（组件）。
//

import SwiftUI

struct MovieGridView: View {
    let title: String
    @ObservedObject var viewModel: MovieListViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if viewModel.movies.isEmpty && viewModel.isLoading {
                ProgressView()
                    .padding(.top, 50)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.movies) { movie in
                    NavigationLink {
                        MovieDetailView(movieID: movie.id)
                    } label: {
                        MovieCoverCard(movie: movie)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(current: movie)
                    }
                }
            }
            .padding(.horizontal)

            if viewModel.isLoading && !viewModel.movies.isEmpty {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.movies.isEmpty {
                await viewModel.loadMore()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}
