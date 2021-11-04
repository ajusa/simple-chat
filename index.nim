import strutils, asyncdispatch, sets, hashes
import karax/[karaxdsl, vdom], jester, ws, ws/jester_extra, json

converter toString(x: VNode): string = $x
template index*(rest: untyped): untyped =
  buildHtml(html(lang = "en")):
    head:
      meta(charset = "UTF-8", name="viewport", content="width=device-width, initial-scale=1")
      link(rel = "stylesheet", href = "https://unpkg.com/@picocss/pico@latest/css/pico.min.css")
      script(src = "https://unpkg.com/htmx.org@1.6.0")
      title: text "Simple Chat"
    body:
      nav(class="container-fluid"):
        ul: li: a(href = "/", class="secondary"): strong: text "Simple Chat"
      main(class="container"): rest
type User = object
  username: string
  socket: WebSocket
proc hash(x: User): Hash = hash(x.username)
proc chatInput(): VNode = buildHtml(input(name="message", id="clearinput", autofocus="", required=""))
proc sendAll(users: HashSet[User], msg: string) =
  for user in users: discard user.socket.send(msg)
template buildMessage*(msg: untyped): untyped =
  buildHtml(p(id="content", hx-swap-oob="beforeend")):
    msg
    br()
var chatrooms = initTable[string, HashSet[User]]()
routes:
  get "/":
    let html = index:
      h1: text "Join a room!"
      form(action="/chat", `method`="get"):
        label:
          text "Room"
          input(type="text", name="room")
        label:
          text "Username"
          input(type="text", name="username")
        input(type="submit", value="Join")
    resp html
  get "/chat":
    let html = index:
      h1: text @"room"
      tdiv(hx-ws="connect:/chat/" & @"room" & "/" & @"username"):
        p(id="content")
        form(hx-ws="send", id="message"): chatInput()
    resp html
  get "/chat/@room/@username":
    var ws = await newWebSocket(request)
    var user = User(username: @"username", socket: ws)
    try:
      chatrooms.mgetOrPut(@"room", initHashSet[User]()).incl(user)
      let joined = buildMessage:
        italic: text user.username
        italic: text " has joined the room"
      chatrooms[@"room"].sendAll(joined)
      while user.socket.readyState == Open:
        let sentMessage = (await user.socket.receiveStrPacket()).parseJson["message"]
        let reply = buildMessage:
          bold: text user.username
          text ": " & sentMessage.getStr()
        discard user.socket.send(chatInput())
        chatrooms[@"room"].sendAll(reply)
    except:
      chatrooms[@"room"].excl(user)
      let left = buildMessage:
        italic: text user.username
        italic: text " has left the room"
      chatrooms[@"room"].sendAll(left)
    resp "" # need this so jester doesn't throw a fit
