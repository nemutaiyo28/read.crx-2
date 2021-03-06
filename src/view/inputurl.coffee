app.boot "/view/inputurl.html", ->
  $view = $(document.documentElement)

  app.view_module.view($view)

  $view.find("form").bind "submit", (e) ->
    e.preventDefault()

    url = @url.value
    url = url.replace(/// ^ttp:// ///, "http://")
    unless /// ^h?ttp:// ///.test(url)
      url = "http://" + url
    guess_res = app.url.guess_type(url)
    if guess_res.type is "thread" or guess_res.type is "board"
      app.message.send("open", {url, new_tab: true})
      parent.postMessage(JSON.stringify(type: "request_killme"), location.origin)
    else
      $view
        .find(".notice")
          .hide()
          .text("未対応形式のURLです")
          .fadeIn("fast")
    return
