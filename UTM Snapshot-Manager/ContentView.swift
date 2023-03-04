//
//  ContentView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 03.03.23.
//

import SwiftUI

enum Genre: String, Hashable, CaseIterable {
    case action = "Action"
    case horror = "Horror"
    case ficion = "Fiction"
    case kids = "Kids"
}

struct Movie {
    let name: String
    let genre: Genre
}

struct ContentView: View {
    
    @State private var selectedGenre: Genre?
    
    let movies = [
        Movie(name: "Superman", genre: .action),
        Movie(name: "28 Days Later", genre: .horror),
        Movie(name: "World War Z", genre: .horror),
        Movie(name: "Finding Nemo ", genre: .kids)
    ]
    
    let columns: [GridItem] = [.init(.fixed(400)), .init(.fixed(400))]
    
    var body: some View {
        NavigationSplitView {
            List(Genre.allCases, id: \.self, selection: $selectedGenre) { genre in
                NavigationLink(genre.rawValue, value: genre)
            }
        } detail: {
            let filteredMovies = movies.filter { $0.genre == selectedGenre}
            
            LazyVGrid(columns: columns) {
                ForEach(filteredMovies, id: \.name) { movie in
                    Text(movie.name)
                        .frame(width: 200, height: 200)
                        .foregroundColor(.white)
                        .background(content: { Color.gray})
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
