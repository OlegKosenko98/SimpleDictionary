//
//  WODDataProvider.swift
//  SimpleDictionary
//
//  Created by Oleg Kosenko on 2020-11-14.
//

import UIKit
import Combine
import ComposableArchitecture
import AVFoundation

class SearchDataProvider {
    
    
    // MARK: - Private Properties
    
    private let apiService: APIService
    private let coreDataService: CoreDataService
    
    private var wordAudioPlayer: AVAudioPlayer?
    private var soundsCache = [String : Data]()
    
    private let textChecker = UITextChecker()
    
    
    // MARK: - Init
    
    init(apiService: APIService, coreDataService: CoreDataService) {
        self.apiService = apiService
        self.coreDataService = coreDataService
    }
    
    
    // MARK: - Word Suggestions
    
    func fetchWordSuggestions(for query: String) -> Effect<[String], Never> {
        guard !query.isBlank else { return .init(value: []) }
        
        return [query].publisher
            .map { query in
                let targetText = String(query.split(separator: " ").last!)
                let range = NSRange(targetText.startIndex..<targetText.endIndex, in: targetText)
                let completions = textChecker.completions(forPartialWordRange: range, in: targetText, language: "en")
                var result = completions ?? []
                if result.isEmpty {
                    let guesses = textChecker.guesses(forWordRange: range, in: targetText, language: "en")
                    result.append(contentsOf: guesses ?? [])
                }
                
                let indexOfQuery = result.firstIndex { $0 == query }
                if let index = indexOfQuery {
                    result.remove(at: index)
                }
                result.insert(query, at: 0)
                
                return result
            }
            .eraseToEffect()
    }
    
    
    // MARK: - Word of the Day
    
    func fetchWODs() -> Effect<[WordnikWODNormalized], Never> {
        let requiredCount = 7
        var dateComponents = DateComponents()
        var requiredDates = [String : Date]()
        
        for day in 0..<requiredCount {
            dateComponents.day = -day
            let date = Date().changed(with: dateComponents)
            requiredDates[date.yearMonthDayLocal] = date /// yearMonthDay returns date in local timeZone
        }

        return coreDataService.fetchWords(ofType: .wod)
            .replaceError(with: [])
            .flatMap { dbWords -> AnyPublisher<[WordnikWODNormalized], Never> in
                var mutableDBWords = dbWords
                
                var wordsToRemove = [Word]()
                mutableDBWords.removeAll { word in
                    if requiredDates.removeValue(forKey: word.normalizedDate.yearMonthDayUTC0) == nil {
                        wordsToRemove.append(word)
                        return true
                    } else {
                        return false
                    }
                }

                /// Delete old words
                self.coreDataService.deleteWords(wordsToRemove)
                
                /// Requesting absent words from API, parsing them, saving to the DB
                let remotePublisher = requiredDates.publisher
                    .flatMap { _, date -> AnyPublisher<WordnikWOD, APIError> in
                        self.apiService.GET(endpoint: .wordnik(.wod(date: date)))
                    }
                    .mapError { $0 as Error }
                    .compactMap { WordnikWODNormalized(wordnikWod: $0) }
                    .map { wodNormalized -> WordnikWODNormalized in
                        self.saveWOD(word: wodNormalized)
                        return wodNormalized
                    }
                
                /// Parsing words from DB
                let dbPublisher = mutableDBWords.publisher
                    .compactMap { word -> WordnikWODNormalized? in
                        WordnikWODNormalized(word: word)
                    }
                    .mapError { $0 as Error }
                
                /// Merging them together into one array
                return remotePublisher.merge(with: dbPublisher)
                    /// Replace errors with nil value, so even when API does not return any requested words, we can show smth from DB
                    .map { word -> WordnikWODNormalized? in word }
                    .replaceError(with: nil)
                    .compactMap { $0 }
                    ///
                    .collect()
                    .eraseToAnyPublisher()
            }
            .eraseToEffect()
    }
    
    func saveWOD(word: WordnikWODNormalized) {
        coreDataService.addWord(ofType: .wod,
                                title: word.title,
                                date: word.date,
                                definitions: [word.partOfSpeech : [word.definition]])
    }
    
    
    // MARK: - Search Results
    
    func fetchUrbanDictionary(for word: String) -> Effect<UrbanEntry, Never> {
        [word.lowercased()].publisher
            .flatMap { word -> AnyPublisher<UrbanEntry, APIError> in
                self.apiService.GET(endpoint: .urban(.definitions(word: word)))
            }
            .replaceError(with: UrbanEntry(list: []))
            .eraseToEffect()
    }
    
    func fetchMerriamWebsterDictionary(for word: String) -> Effect<MerriamWebsterEntry, Never> {
        [word.lowercased()].publisher
            .flatMap { word -> AnyPublisher<MerriamWebsterEntry, APIError> in
                self.apiService.GET(endpoint: .merriamWebster(.definitions(word: word)))
            }
            .map { entry -> MerriamWebsterEntry? in
                return entry
            }
            .replaceError(with: nil)
            .compactMap { $0 }
            .eraseToEffect()
    }
    
    func fetchOxfordDictionary(for word: String) -> Effect<StandardDictionaryEntry, Error> {
        [word.lowercased()].publisher
            .flatMap { word -> AnyPublisher<OxfordEntry, APIError> in
                self.apiService.GET(endpoint: .oxford(.definitions(word: word)))
            }
            .map { entry -> StandardDictionaryEntry? in
                StandardDictionaryEntry(oxfordEntry: entry)
            }
            .compactMap { $0 }
            .mapError { $0 as Error}
            .eraseToEffect()
    }
    
    
    // MARK: - Audio
    
    func fetchDefaultAudio(for word: String) -> Effect<Bool, Never> {
        let lowercasedWord = word.lowercased()
        if let cachedData = soundsCache[lowercasedWord], let player = try? AVAudioPlayer(data: cachedData) {
            wordAudioPlayer = player
            return .init(value: true)
        }
        
        return [lowercasedWord].publisher
            .flatMap { word -> AnyPublisher<[WordnikAudio], APIError> in
                self.apiService.GET(endpoint: .wordnik(.audio(word)))
            }
            .mapError { $0 as Error }
            .compactMap { $0.last }
            .compactMap { wordnikAudio -> URL? in
                if let fileUrl = wordnikAudio.fileUrl, let url = URL(string: fileUrl) {
                    return url
                }
                return nil
            }
            .flatMap { url -> AnyPublisher<Bool, Error> in
                self.fetchAudio(with: url, for: lowercasedWord)
            }
            .replaceError(with: false)
            .eraseToEffect()
    }
    
    func fetchAudio(with url: URL, for word: String) -> AnyPublisher<Bool, Error> {
        [url].publisher
            .flatMap { url -> AnyPublisher<(data: Data, response: URLResponse), Error> in
                URLSession.shared.dataTaskPublisher(for: url)
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .tryMap { data, _ -> AVAudioPlayer in
                let player = try AVAudioPlayer(data: data)
                self.soundsCache[word.lowercased()] = data
                return player
            }
            .map { player -> Bool in
                self.wordAudioPlayer = player
                self.wordAudioPlayer?.prepareToPlay()
                return true
            }
            .eraseToAnyPublisher()
    }
    
    func playWordAudioIfAvailable() {
        guard let player = wordAudioPlayer else { return }
        player.play()
    }
    
    func resetAudioPlayer() {
        wordAudioPlayer?.stop()
        wordAudioPlayer = nil
    }
}
