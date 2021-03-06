do ->
  return if /windows/i.test(navigator.userAgent)
  if "textar_font" of localStorage
    $ ->
      style = document.createElement("style")
      style.textContent = """
        @font-face {
          font-family: "Textar";
          src: url(#{localStorage.textar_font});
        }
      """
      document.head.appendChild(style)
      return
  return

app.boot "/write/write.html", ->
  arg = app.url.parse_query(location.href)
  arg.url = app.url.fix(arg.url)
  arg.title or= arg.url
  arg.name or= app.config.get("default_name")
  arg.mail or= app.config.get("default_mail")
  arg.message or= ""

  chrome.tabs.getCurrent (tab) ->
    chrome.webRequest.onBeforeSendHeaders.addListener(
      (req) ->
        origin = chrome.extension.getURL("")[...-1]
        is_same_origin = req.requestHeaders.some((header) -> header.name is "Origin" and header.value is origin)
        if req.method is "POST" and is_same_origin
          if (
            ///^http://\w+\.2ch\.net/test/bbs\.cgi ///.test(req.url) or
            ///^http://jbbs\.livedoor\.jp/bbs/write\.cgi/ ///.test(req.url)
          )
            req.requestHeaders.push(name: "Referer", value: arg.url)
            return requestHeaders: req.requestHeaders
        return
      {
        tabId: tab.id
        types: ["sub_frame"]
        urls: [
          "http://*.2ch.net/test/bbs.cgi*"
          "http://jbbs.livedoor.jp/bbs/write.cgi/*"
        ]
      }
      ["requestHeaders", "blocking"]
    )
    return

  $view = $(".view_write")

  $view.find(".preview_button").on "click", (e) ->
    e.preventDefault()

    text = $view.find("textarea").val()
    #行頭のスペースは削除される。複数のスペースは一つに纏められる。
    text = text.replace(/^\u0020*/g, "").replace(/\u0020+/g, " ")

    $("<div>", class: "preview")
      .append($("<pre>", {text}))
      .append(
        $("<button>", class: "close_preview", text: "戻る").on "click", ->
          $(@).parent().remove()
          return
      )
      .appendTo(document.body)
    return

  on_error = (message) ->
    $view.find("form input, form textarea").removeAttr("disabled")

    if message
      $view.find(".notice").text("書き込み失敗 - #{message}")
    else
      $view.find(".notice").text("")
      $view.find(".iframe_container").fadeIn("fast")

    chrome.extension.sendRequest(type: "written?", url: arg.url)

  write_timer =
    wake: ->
      if @timer? then @kill()
      @timer = setTimeout ->
        on_error("一定時間経過しても応答が無いため、処理を中断しました")
      , 1000 * 30
    kill: ->
      clearTimeout(@timer)
      @timer = null

  window.addEventListener "message", (e) ->
    message = JSON.parse(e.data)
    if message.type is "ping"
      e.source.postMessage("write_iframe_pong", "*")
      write_timer.wake()
    else if message.type is "success"
      $view.find(".notice").text("書き込み成功")
      setTimeout ->
        chrome.extension.sendRequest(type: "written", url: arg.url)
        chrome.tabs.getCurrent (tab) ->
          chrome.tabs.remove(tab.id)
      , 2000
      write_timer.kill()
    else if message.type is "confirm"
      $view.find(".iframe_container").fadeIn("fast")
      write_timer.kill()
    else if message.type is "error"
      on_error(message.message)
      write_timer.kill()
    return

  $view.find(".hide_iframe").bind "click", ->
    write_timer.kill()
    $view
      .find(".iframe_container")
        .find("iframe")
          .remove()
        .end()
      .fadeOut("fast")
    $view.find("input, textarea").removeAttr("disabled")
    $view.find(".notice").text("")
    return

  document.title = arg.title
  $view.find("h1").text(arg.title)
  $view.find(".name").val(arg.name)
  $view.find(".mail").val(arg.mail)
  $view.find(".message").val(arg.message)

  $view.find("form").bind "submit", (e) ->
    e.preventDefault()

    $view.find("input, textarea").attr("disabled", true)

    guess_res = app.url.guess_type(arg.url)

    iframe_arg =
      rcrx_name: $view.find(".name").val()
      rcrx_mail: $view.find(".mail").val()
      rcrx_message: $view.find(".message").val()

    #p2
    if app.config.get("p2_write") is "on" and ((guess_res.bbs_type is "2ch" and app.url.tsld(arg.url) is "2ch.net") or guess_res.bbs_type is "jbbs")
      if not /^w\d+\.p2\.2ch\.net$/.test(app.config.get("p2_server"))
        on_error("p2のサーバー設定が誤っています")
        return

      if res = ///^http://(\w+\.2ch\.net)/test/read\.cgi/(\w+)/(\d+)///.exec(arg.url)
        iframe_arg.host = res[1]
        iframe_arg.bbs = res[2]
        iframe_arg.key = res[3]
      else if res = ///^http://jbbs\.livedoor\.jp/bbs/read\.cgi/(\w+)/(\d+)/(\d+)///.exec(arg.url)
        iframe_arg.host = "jbbs.livedoor.jp/#{res[1]}"
        iframe_arg.bbs = res[2]
        iframe_arg.key = res[3]

      iframe_url = "http://#{app.config.get("p2_server")}"
      iframe_url += "/p2/post_form.php?"
      iframe_arg.expected_url = iframe_url
      iframe_url += app.url.build_param(iframe_arg)

    $iframe = $("<iframe>", src: iframe_url or "/view/empty.html")
    unless iframe_url?
      $iframe.one "load", ->
        #2ch
        if guess_res.bbs_type is "2ch"
          tmp = arg.url.split("/")
          form_data =
            action: "http://#{tmp[2]}/test/bbs.cgi"
            charset: "Shift_JIS"
            input:
              submit: "書きこむ"
              time: Math.floor(Date.now() / 1000) - 60
              bbs: tmp[5]
              key: tmp[6]
              FROM: iframe_arg.rcrx_name
              mail: iframe_arg.rcrx_mail
            textarea:
              MESSAGE: iframe_arg.rcrx_message
        #したらば
        else if guess_res.bbs_type is "jbbs"
          tmp = arg.url.split("/")
          form_data =
            action: "http://jbbs.livedoor.jp/bbs/write.cgi/#{tmp[5]}/#{tmp[6]}/#{tmp[7]}/"
            charset: "EUC-JP"
            input:
              TIME: Math.floor(Date.now() / 1000) - 60
              DIR: tmp[5]
              BBS: tmp[6]
              KEY: tmp[7]
              NAME: iframe_arg.rcrx_name
              MAIL: iframe_arg.rcrx_mail
            textarea:
              MESSAGE: iframe_arg.rcrx_message
        #フォーム生成
        form = @contentWindow.document.createElement("form")
        form.setAttribute("accept-charset", form_data.charset)
        form.action = form_data.action
        form.method = "POST"
        for key, val of form_data.input
          input = @contentWindow.document.createElement("input")
          input.name = key
          input.setAttribute("value", val)
          form.appendChild(input)
        for key, val of form_data.textarea
          textarea = @contentWindow.document.createElement("textarea")
          textarea.name = key
          textarea.textContent = val
          form.appendChild(textarea)
        form.__proto__.submit.call(form)
        return
    $iframe.appendTo(".iframe_container")

    write_timer.wake()

    $view.find(".notice").text("書き込み中")
  return
