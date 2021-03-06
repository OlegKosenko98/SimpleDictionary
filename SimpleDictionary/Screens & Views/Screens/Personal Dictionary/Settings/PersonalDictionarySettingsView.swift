//
//  PersonalDictionarySettingsView.swift
//  SimpleDictionary
//
//  Created by Oleg Kosenko on 2020-11-28.
//

import SwiftUI
import ComposableArchitecture

struct PersonalDictionarySettingsView: View {
    let store: Store<PersonalDictionarySettingsState, PersonalDictionarySettingsAction>
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        WithViewStore(store) { viewStore in
            NavigationView {
                
                VStack {
                    Form {
                        Section {
                            Toggle(isOn: viewStore.binding(get: { $0.settings.isDictionaryDateShown },
                                                           send: PersonalDictionarySettingsAction.toggleChange)) {
                                Text("Show date")
                                    .fontWeight(.regular)
                            }
                        }
                    }
                }
                .navigationBarItems(trailing: Button("Done", action: { presentationMode.wrappedValue.dismiss() }))
                .navigationBarTitle("Settings", displayMode: .inline)
            }
            .onAppear { viewStore.send(.onAppear) }
        }
    }
    
}
