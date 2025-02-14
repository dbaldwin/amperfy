import Foundation
import CoreData
import os.log

class AmpacheLibraryBackgroundSyncer: GenericLibraryBackgroundSyncer, BackgroundLibrarySyncer {
    
    private let ampacheXmlServerApi: AmpacheXmlServerApi

    init(ampacheXmlServerApi: AmpacheXmlServerApi) {
        self.ampacheXmlServerApi = ampacheXmlServerApi
    }

    func syncInBackground(libraryStorage: LibraryStorage) {
        isRunning = true
        semaphoreGroup.enter()
        isActive = true
        
        if let latestSyncWave = libraryStorage.getLatestSyncWave(), !latestSyncWave.isDone {
            os_log("Lib resync: Continue last resync", log: log, type: .info)
            resync(libraryStorage: libraryStorage, syncWave: latestSyncWave, previousAddDate: latestSyncWave.libraryChangeDates.dateOfLastAdd)
        } else if let latestSyncWave = libraryStorage.getLatestSyncWave(),
        let ampacheMetaData = ampacheXmlServerApi.requesetLibraryMetaData(),
        latestSyncWave.libraryChangeDates.dateOfLastAdd != ampacheMetaData.libraryChangeDates.dateOfLastAdd {
            os_log("Lib resync: New changes on server", log: log, type: .info)
            let syncWave = libraryStorage.createSyncWave()
            syncWave.setMetaData(fromLibraryChangeDates: ampacheMetaData.libraryChangeDates)
            libraryStorage.saveContext()
            resync(libraryStorage: libraryStorage, syncWave: syncWave, previousAddDate: latestSyncWave.libraryChangeDates.dateOfLastAdd)
        } else {
            os_log("Lib resync: No changes", log: log, type: .info)
        }
        
        isActive = false
        semaphoreGroup.leave()
    }   
    
    private func resync(libraryStorage: LibraryStorage, syncWave: SyncWaveMO, previousAddDate: Date) {
        // Add one second to previouseAddDate to avoid resyncing previous sync Wave
        let addDate = Date(timeInterval: 1, since: previousAddDate)

        if syncWave.syncState == .Artists, isRunning {
            var allParsed = false
            repeat {
                let artistParser = ArtistParserDelegate(libraryStorage: libraryStorage, syncWave: syncWave, ampacheUrlCreator: ampacheXmlServerApi)
                ampacheXmlServerApi.requestArtists(parserDelegate: artistParser, addDate: addDate, startIndex: syncWave.syncIndexToContinue, pollCount: AmpacheXmlServerApi.maxItemCountToPollAtOnce)
                syncWave.syncIndexToContinue += artistParser.parsedCount
                allParsed = artistParser.parsedCount == 0
            } while(!allParsed && isRunning)

            if allParsed {
                os_log("Lib resync: %d Artists parsed", log: log, type: .info, syncWave.syncIndexToContinue)
                syncWave.syncState = .Albums
            }
            libraryStorage.saveContext()
        }
        if syncWave.syncState == .Albums, isRunning {
            var allParsed = false
            repeat {
                let albumParser = AlbumParserDelegate(libraryStorage: libraryStorage, syncWave: syncWave)
                ampacheXmlServerApi.requestAlbums(parserDelegate: albumParser, addDate: addDate, startIndex: syncWave.syncIndexToContinue, pollCount: AmpacheXmlServerApi.maxItemCountToPollAtOnce)
                syncWave.syncIndexToContinue += albumParser.parsedCount
                allParsed = albumParser.parsedCount == 0
            } while(!allParsed && isRunning)

            if allParsed {
                os_log("Lib resync: %d Albums parsed", log: log, type: .info, syncWave.syncIndexToContinue)
                syncWave.syncState = .Songs
            }
            libraryStorage.saveContext()
        }
        if syncWave.syncState == .Songs, isRunning {
            var allParsed = false
            repeat {
                let songParser = SongParserDelegate(libraryStorage: libraryStorage, syncWave: syncWave)
                ampacheXmlServerApi.requestSongs(parserDelegate: songParser, addDate: addDate, startIndex: syncWave.syncIndexToContinue, pollCount: AmpacheXmlServerApi.maxItemCountToPollAtOnce)
                syncWave.syncIndexToContinue += songParser.parsedCount
                allParsed = songParser.parsedCount == 0
            } while(!allParsed && isRunning)

            if allParsed {
                os_log("Lib resync: %d Songs parsed", log: log, type: .info, syncWave.syncIndexToContinue)
                syncWave.syncState = .Done
            }
            libraryStorage.saveContext()
        }
    }

}
