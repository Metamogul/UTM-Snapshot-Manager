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
    
    var buttonTitle: LocalizedStringKey
    var buttonAction: () -> Void = {}
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presentingSheet) {
                Form {
                    TextField(nameFieldTitle, text: $name)
                        .frame(minWidth: nameFieldMinWidth)
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
                Button(mainButtonTitle, action: mainButtonActionAndDismissDialog)
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
        nameFieldTitle: LocalizedStringKey = LocalizedStringKey("Tag for new Snapshot:"),
        nameFieldMinWidth: CGFloat = 250,
        buttonTitle: LocalizedStringKey = LocalizedStringKey("Create"),
        buttonAction: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            NameSheetModifier(presentingSheet: presentingSheet,
                              name: name,
                              nameFieldTitle: nameFieldTitle,
                              nameFieldMinWidth: nameFieldMinWidth,
                              buttonTitle: buttonTitle,
                              buttonAction: buttonAction)
        )
    }
    
    func snapshotManagerDialog(
        presentingDialog: Binding<Bool>,
        title: LocalizedStringKey,
        mainButtonTitle: LocalizedStringKey,
        mainButtonAction: @escaping () -> Void = {}
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
        mainButtonAction: @escaping () -> Void = {}
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
