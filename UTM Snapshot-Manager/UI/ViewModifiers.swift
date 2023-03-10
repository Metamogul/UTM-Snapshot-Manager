//
//  NameSheetModifier.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 10.03.23.
//

import SwiftUI

struct NameSheetModifier: ViewModifier {
    @Binding var presentingSheet: Bool
    @Binding var name: String
    
    var nameFieldTitle = LocalizedStringKey("Name:")
    var nameFieldMinWidth = CGFloat(150)
    var nameFieldRestrictFormat = false
    
    var buttonTitle: LocalizedStringKey
    var buttonAction: () -> Void = {}
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presentingSheet) {
                Form {
                    if !nameFieldRestrictFormat {
                        TextField(nameFieldTitle, text: $name)
                            .frame(minWidth: nameFieldMinWidth)
                    } else {
                        TextField(nameFieldTitle, value: $name, format: SnapshotStyle())
                            .frame(minWidth: nameFieldMinWidth)
                    }
                    Button(buttonTitle, action: buttonActionAndDismissSheet)
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
                .onAppear {
                    self.name = ""
                }
            }
    }
    
    func buttonActionAndDismissSheet() {
        self.buttonAction()
        presentingSheet = false
    }
    
    struct SnapshotStyle: ParseableFormatStyle {
        var parseStrategy: ParseSnapshotTagStrategy = .init()
        
        func format(_ value: String /*Tag*/) -> String {
            return value
        }
    }
    
    struct ParseSnapshotTagStrategy: ParseStrategy {
        static let illegalCharacters = " $/\""
        
        func parse(_ value: String) throws -> String /*Tag*/ {
            return value.filter { !Self.illegalCharacters.contains($0) }
        }
    }
}

struct SnapshotManagerDialogModifier: ViewModifier {
    @Binding var presentingDialog: Bool
    
    var title: LocalizedStringKey
    
    var mainButtonTitle: LocalizedStringKey
    var mainButtonRole: ButtonRole?
    var mainButtonAction: () -> Void = {}
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $presentingDialog) {
                Button(mainButtonTitle, role: mainButtonRole, action: mainButtonActionAndDismissDialog)
                    .keyboardShortcut(.defaultAction)
            }
    }
    
    func mainButtonActionAndDismissDialog() {
        self.mainButtonAction()
        presentingDialog = false
    }
}

extension View {
    func nameSheet(
        presentingSheet: Binding<Bool>,
        name: Binding<String>,
        nameFieldTitle: LocalizedStringKey = LocalizedStringKey("Name:"),
        nameFieldMinWidth: CGFloat = 150,
        buttonTitle: LocalizedStringKey,
        buttonAction: @escaping () -> Void = {}
    ) -> some View {
        return modifier(
            NameSheetModifier(presentingSheet: presentingSheet,
                              name: name,
                              nameFieldTitle: nameFieldTitle,
                              nameFieldMinWidth: nameFieldMinWidth,
                              buttonTitle: buttonTitle,
                              buttonAction: buttonAction)
        )
    }
    
    func newSnapshotSheet(
        presentingSheet: Binding<Bool>,
        name: Binding<String>,
        buttonAction: @escaping () -> Void
    ) -> some View {
        modifier(
            NameSheetModifier(presentingSheet: presentingSheet,
                              name: name,
                              nameFieldTitle: LocalizedStringKey("Tag for new Snapshot:"),
                              nameFieldMinWidth: 250,
                              nameFieldRestrictFormat: true,
                              buttonTitle: LocalizedStringKey("Create"),
                              buttonAction: buttonAction)
        )
    }
    
    func snapshotManagerDialog(
        presentingDialog: Binding<Bool>,
        title: LocalizedStringKey,
        mainButtonTitle: LocalizedStringKey,
        mainButtonAction: @escaping () -> Void
    ) -> some View {
        modifier(
            SnapshotManagerDialogModifier(presentingDialog: presentingDialog,
                                   title: title,
                                   mainButtonTitle: mainButtonTitle,
                                   mainButtonAction: mainButtonAction)
        )
    }
    
    func snapshotManagerDialog(
        presentingDialog: Binding<Bool>,
        title: LocalizedStringKey,
        mainButtonTitle: LocalizedStringKey,
        mainButtonRole: ButtonRole?,
        mainButtonAction: @escaping () -> Void
    ) -> some View {
        modifier(
            SnapshotManagerDialogModifier(presentingDialog: presentingDialog,
                                   title: title,
                                   mainButtonTitle: mainButtonTitle,
                                   mainButtonRole: mainButtonRole,
                                   mainButtonAction: mainButtonAction)
        )
    }
}
