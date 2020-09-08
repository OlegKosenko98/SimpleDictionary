//
//  DictionaryEntryView.swift
//  SimpleDictionary
//
//  Created by Oleg Kosenko on 2020-09-07.
//

import SwiftUI

struct DictionaryEntryView: View {
    
    @StateObject private var viewModel: DictionaryEntryViewModel
    
    init(lexicalEntry: LexicalEntry) {
        _viewModel = StateObject(wrappedValue: DictionaryEntryViewModel(lexicalEntry: lexicalEntry))
    }
    
    var body: some View {
        VStack {
            Dropdown(dropdownHeadlineText: viewModel.text, dropdownItems: Set(viewModel.examples))
        }
            
    }
}

struct DictionaryEntryView_Previews: PreviewProvider {
    static var previews: some View {
        DictionaryEntryView(lexicalEntry: staticLexicalEntry)
    }
}
