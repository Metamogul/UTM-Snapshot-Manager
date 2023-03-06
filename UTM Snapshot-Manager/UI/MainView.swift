//
//  ContentView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 03.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

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

struct MainView: View {
    
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
            
            VStack {
                LazyVGrid(columns: columns) {
                    ForEach(filteredMovies, id: \.name) { movie in
                        Text(movie.name)
                            .frame(width: 200, height: 200)
                            .foregroundColor(.white)
                            .background(content: { Color.gray})
                    }
                }
                Button {
                    MainView.createDemoVMGroup()
                } label: {
                    Text("Create demo VM group")
                }

            }
            
        }
    }
    
    private static func showOpenPanel() -> [URL]? {
        let utmType = UTType(filenameExtension: "utm", conformingTo: .package)
        let openPanel = NSOpenPanel()
        
        openPanel.allowedContentTypes = [utmType!]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        
        let response = openPanel.runModal()
        return response == .OK ? openPanel.urls : nil
    }
    
    private static func createDemoVMGroup() {
        guard let baseUrls = self.showOpenPanel() else {
            return
        }
        
        let vmUrls = FileManager.utmPackageURLsAt(baseUrls)
        let vms = vmUrls
            .filter { FileManager.isValidUTMPackageUrl($0) }
            .map { VM(validatedUrl: $0) }
        let vmTestGroup = VMGroup(id: UUID(), name: "Test", vms: vms)
        
        UserSettings().vmGroups.append(vmTestGroup)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
