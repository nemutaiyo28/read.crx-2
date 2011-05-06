`/** @namespace */`
app.read_state = {}

app.read_state.get = (url, callback) ->
  req = webkitIndexedDB.open("read_state")
  req.onerror = ->
    callback(status: "error")
    app.log("error", "app.read_state.get: データベースへの接続に失敗")
  req.onsuccess = ->
    db = req.result
    if db.version isnt "1"
      app.log("warn", "app.read_state.get: 予期せぬdb.version", db.version)
      db.close()
      callback(status: "error")
    else
      tra = db.transaction(["read_state"], webkitIDBTransaction.READ_ONLY)
      tra.oncomplete = ->
        db.close()
      tra.onerror = ->
        db.close()

      objectStore = tra.objectStore("read_state")
      req = objectStore.get(url)
      req.onsuccess = ->
        if typeof req.result is "object"
          callback(status: "success", data: req.result)
        else
          callback(status: "not_fount")
      req.onerror = ->
        callback(status: "error")

app.read_state.get_by_board = (board_url, callback) ->
  app.log("warn", "app.read_state.get_by_boardは未実装です")
  callback(status: "error")

app.read_state.set = (url, read_state) ->
  $.Deferred (deferred) ->
      if (
        typeof url is "string" and
        typeof read_state.last is "number" and
        typeof read_state.read is "number" and
        typeof read_state.received is "number"
      )
        read_state.url = url
        #todo
        read_state.board_url = null
        deferred.resolve()
      else
        app.log("error", "app.read_state.set: 引数が不正です", arguments)
        deferred.reject()

    .pipe ->
      deferred = $.Deferred()
      req = webkitIndexedDB.open("read_state")
      req.onerror = ->
        app.log("error", "app.read_state.set: データベースへの接続に失敗")
        deferred.reject()
      req.onsuccess = ->
        deferred.resolve(req.result)
      deferred

    .pipe (db) ->
      deferred = $.Deferred()
      if db.version isnt "1"
        req = db.setVersion("1")
        req.onerror = ->
          app.log("error", "app.read_state.set: db.setVersion失敗(%s -> %s)", db.version, "1")
          deferred.reject(db)
        req.onsuccess = ->
          db.createObjectStore("read_state", keyPath: "url")
          app.log("info", "app.read_state.set: db.setVersion成功(%s -> %s)", db.version, "1")
          deferred.resolve(db)
      else
        deferred.resolve(db)
      deferred

    .pipe (db) ->
      deferred = $.Deferred()
      transaction = db.transaction(["read_state"], webkitIDBTransaction.READ_WRITE)
      transaction.onerror = ->
        app.log("error", "app.read_state.set: 保存失敗")
        deferred.reject(db)
      transaction.oncomplete = ->
        deferred.resolve(db)
      transaction
        .objectStore("read_state")
          .put(read_state)
      deferred

    .always (db) ->
      db and db.close()