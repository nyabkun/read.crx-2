app.thread = {}

app.thread._get_xhr_info = (thread_url) ->
  tmp = ///^http://(\w+\.(\w+\.\w+))/(?:test|bbs)/read\.cgi/
    (\w+)/(\d+)/(?:(\d+)/)?$///.exec(thread_url)
  if not tmp
    return null

  switch tmp[2]
    when "machi.to"
      path: "http://#{tmp[1]}/bbs/offlaw.cgi/#{tmp[3]}/#{tmp[4]}/",
      charset: "Shift_JIS"
    when "livedoor.jp"
      path: "http://jbbs.livedoor.jp/" +
          "bbs/rawmode.cgi/#{tmp[3]}/#{tmp[4]}/#{tmp[5]}/",
      charset: "EUC-JP"
    else
      path: "http://#{tmp[1]}/#{tmp[3]}/dat/#{tmp[4]}.dat",
      charset: "Shift_JIS"

###
promiseを返す
キャッシュ取得成功時
notify
  type: "cache_found", data: thread, [message]
通信完了
resolve
  type: "success", data: thread, [message]
通信失敗 reject
resolve
  type: "error", [data: thread], [message]
###
app.thread.get = (url, force_update) ->
  res_deferred = $.Deferred()

  xhr_info = app.thread._get_xhr_info(url)
  return res_deferred.reject().promise() unless xhr_info
  xhr_path = xhr_info.path
  xhr_charset = xhr_info.charset

  delta_flg = false

  #キャッシュ取得
  app.cache.get(xhr_path)
    .pipe (cache) ->
      $.Deferred (deferred) ->
        if force_update or Date.now() - cache.data.last_updated > 1000 * 3
          #通信が生じる場合のみ、notifyでキャッシュを送出する
          app.defer ->
            res_deferred.notify(type: "cache_found", data: app.thread.parse(url, cache.data.data))
          deferred.reject(cache)
        else
          deferred.resolve(cache)

    #通信
    .pipe null, (cache) ->
      $.Deferred (deferred) ->
        tmp_xhr_path = xhr_path
        if app.url.tsld(url) is "livedoor.jp" or app.url.tsld(url) is "machi.to"
          if cache.status is "success"
            delta_flg = true
            tmp_xhr_path += (+cache.data.res_length + 1) + "-"

        ajax_data =
          url: tmp_xhr_path
          bforeSend: undefined
          cache: false
          dataType: "text"
          headers: {}
          mimeType: "text/plain; charset=#{xhr_charset}"
          timeout: 1000 * 30
          complete: ($xhr) ->
            if $xhr.status is 200
              deferred.resolve(cache, $xhr)
            else if cache.status is "success" and $xhr.status is 304
              deferred.resolve(cache, $xhr)
            else
              deferred.reject(cache, $xhr)

        if cache.status is "success"
          if cache.data.last_modified?
            ajax_data.headers["If-Modified-Since"] = new Date(cache.data.last_modified).toUTCString()
          if cache.data.etag?
            ajax_data.headers["If-None-Match"] = cache.data.etag

        $.ajax(ajax_data)

    #パース
    .pipe((fn = (cache, $xhr) ->
      $.Deferred (deferred) ->
        guess_res = app.url.guess_type(url)

        if $xhr?.status is 200
          if delta_flg
            thread = app.thread.parse(url, cache.data.data + $xhr.responseText)
          else
            thread = app.thread.parse(url, $xhr.responseText)
        #2ch系BBSのdat落ち
        else if guess_res.bbs_type is "2ch" and $xhr?.status is 203
          if cache?.status is "success"
            thread = app.thread.parse(url, cache.data.data)
          else
            thread = app.thread.parse(url, $xhr.responseText)
        else if cache?.status is "success"
          thread = app.thread.parse(url, cache.data.data)

        #パース成功
        if thread
          #通信成功
          if $xhr?.status is 200 or
              #通信成功（更新なし）
              $xhr?.status is 304 or
              #キャッシュが期限内だった場合
              (not $xhr and cache?.status is "success")
            deferred.resolve(cache, $xhr, thread)
          #2ch系BBSのdat落ち
          else if guess_res.bbs_type is "2ch" and $xhr?.status is 203
            deferred.reject(cache, $xhr, thread)
          else
            deferred.reject(cache, $xhr, thread)
        #パース失敗
        else
          deferred.reject(cache, $xhr)
    ), fn)

    #コールバック
    .done (cache, $xhr, thread) ->
      res_deferred.resolve(type: "success", data: thread)

    .fail (cache, $xhr, thread) ->
      message = ""

      #2chでrejectされてる場合は移転を疑う
      if app.url.tsld(url) is "2ch.net" and $xhr
        app.util.ch_server_move_detect(app.url.thread_to_board(url))
          #移転検出時
          .done (new_board_url) ->
            tmp = ///^http://(\w+)\.2ch\.net/ ///.exec(new_board_url)[1]
            new_url = url.replace(
              ///^(http://)\w+(\.2ch\.net/test/read\.cgi/\w+/\d+/)$///,
              ($0, $1, $2) -> $1 + tmp + $2
            )

            #TODO エスケープ用関数を用意
            message += """
            スレッドの読み込みに失敗しました。
            サーバーが移転している可能性が有ります
            (<a href="#{app.safe_href(new_url)}"
              class="open_in_rcrx">#{new_url.replace(/[<>]/g, "")}</a>)
            """
          #移転検出出来なかった場合
          .fail ->
            if $xhr?.status is 203
              message += "dat落ちしたスレッドです。"
            else
              message += "スレッドの読み込みに失敗しました。"
          .always ->
            if cache?.status is "success" and thread
              message += "キャッシュに残っていたデータを表示します。"

            if thread
              res_deferred.reject({type: "error", data: thread, message})
            else
              res_deferred.reject({type: "error", message})
      else
        message += "スレッドの読み込みに失敗しました。"

        if cache?.status is "success" and thread
          message += "キャッシュに残っていたデータを表示します。"

        if thread
          res_deferred.reject({type: "error", data: thread, message})
        else
          res_deferred.reject({type: "error", message})

    #キャッシュ更新部
    .done (cache, $xhr, thread) ->
      #通信に成功した場合
      if $xhr?.status is 200
        old_cache = cache
        cache =
          url: xhr_path
          last_updated: Date.now()
          res_length: thread.res.length

        if delta_flg
          cache.data = old_cache.data.data + $xhr.responseText
        else
          cache.data = $xhr.responseText

        last_modified = new Date(
          $xhr.getResponseHeader("Last-Modified") or "dummy"
        ).getTime()

        if not isNaN(last_modified)
          cache.last_modified = last_modified

        etag = $xhr.getResponseHeader("ETag")
        if etag
          cache.etag = etag

        app.cache.set(cache)

      #304だった場合はアップデート時刻のみ更新
      else if cache?.status is "success" and $xhr?.status is 304
        cache.data.last_updated = Date.now()
        app.cache.set(cache.data)

    #ブックマーク更新部
    .always (cache, $xhr, thread) ->
      #キャッシュが残っていればthreadはキャッシュになるので、
      #そのままレス数更新処理を行って大丈夫
      if thread?
        if $xhr?.status is 200 or $xhr?.status is 203
          app.bookmark.update_res_count(url, thread.res.length)

    #dat落ち検出
    .fail (cache, $xhr, thread) ->
      if $xhr?.status is 203
        app.bookmark.update_expired(url, true)

  res_deferred.promise()

app.thread.parse = (url, text) ->
  tmp = /^http:\/\/\w+\.(\w+\.\w+)\//.exec(url)
  if not tmp
    return null
  if tmp[1] is "machi.to"
    return app.thread._parse_machi(text)
  else if tmp[1] is "livedoor.jp"
    return app.thread._parse_jbbs(text)
  else
    return app.thread._parse_ch(text)

app.thread._parse_ch = (text) ->
  # name, mail, other, message, thread_title
  reg = /^(.*?)<>(.*?)<>(.*?)<>(.*?)<>(.*?)(?:<>)?$/

  thread = res: []
  first_flg = true
  for line in text.split("\n")
    reg_res = reg.exec(line)
    if reg_res
      if first_flg
        thread.title = app.util.decode_char_reference(reg_res[5])
        first_flg = false
      thread.res.push
        name: reg_res[1]
        mail: reg_res[2]
        message: reg_res[4]
        other: reg_res[3]
    else
      continue if line is ""
      thread.res.push
        name: "</b>データ破損<b>"
        mail: ""
        message: "データが破損しています"
        other: ""
  if thread.res.length > 0 then thread else null

app.thread._parse_machi = (text) ->
  # res_num, name, mail, other, message, thread_title
  reg = /^(\d+)<>(.*)<>(.*)<>(.*)<>(.*)<>(.*)$/gm

  thread = {res: []}
  res_count = 0
  while (reg_res = reg.exec(text))
    while (++res_count isnt +reg_res[1])
      thread.res.push
        name: "あぼーん"
        mail: "あぼーん"
        message: "あぼーん"
        other: "あぼーん"

    if res_count is 1
      thread.title = app.util.decode_char_reference(reg_res[6])
    thread.res.push
      name: reg_res[2]
      mail: reg_res[3]
      message: reg_res[5]
      other: reg_res[4]

  if thread.res.length > 0 then thread else null

app.thread._parse_jbbs = (text) ->
  # res_num, name, mail, date, message, thread_title, id
  reg = /^(\d+)<>(.*)<>(.*)<>(.*)<>(.*)<>(.*)<>(.*)$/gm

  thread = {res: []}
  res_count = 0
  while (reg_res = reg.exec(text))
    while (++res_count isnt +reg_res[1])
      thread.res.push
        name: "あぼーん"
        mail: "あぼーん"
        message: "あぼーん"
        other: "あぼーん"

    if res_count is 1
      thread.title = app.util.decode_char_reference(reg_res[6])
    thread.res.push
      name: reg_res[2]
      mail: reg_res[3]
      message: reg_res[5]
      other: reg_res[4] + if reg_res[7] then " ID:" + reg_res[7] else ""
  if thread.res.length > 0 then thread else null
