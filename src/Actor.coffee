@WebActors ?= {}

class NullActor
  constructor: ->
    @actor_id = null

  link: (actor_id) ->
    throw "No current actor"

  unlink: (actor_id) ->
    throw "No current actor"

  send: (message) ->

  kill: (killer_id, reason) ->

  trap_kill: (handler) ->
    throw "No current actor"

  receive: (pattern, cont) ->
    throw "No current actor"

NULL_ACTOR = new NullActor()
current_actor = NULL_ACTOR

class DeadActor
  constructor: (@actor_id) ->

  link: (actor_id) ->
    actor = new RemoteActor(actor_id)
    actor.kill(@actor_id, "actor is dead or unreachable")

  unlink: (actor_id) ->

  send: (message) ->

  kill: (killer_id, reason) ->

class RemoteActor
  constructor: (@actor_id) ->

  route: (verb, param) ->
    get_router().route_message(@actor_id, verb, param)

  link: (actor_id) ->
    @route "link", actor_id

  unlink: (actor_id) ->
    @route "unlink", actor_id

  send: (message) ->
    @route "send", message

  kill: (killer_id, reason) ->
    @route "kill", [killer_id, reason]

class LocalActor
  constructor: (@actor_id) ->
    @mailbox = new WebActors.Mailbox()
    @killed = false
    @state = {}
    @clauses = null
    @kill_handler = null
    @linked = {}

  link: (actor_id) ->
    @linked[actor_id] = true

  unlink: (actor_id) ->
    delete @linked[actor_id]

  send: (message) ->
    @mailbox.postMessage(message)

  kill: (killer_id, reason) ->
    if @kill_handler
      saved_actor = current_actor
      current_actor = NULL_ACTOR
      try
        @kill_handler(killer_id, reason)
      catch e
        @shutdown(e)
      finally
        current_actor = saved_actor
    else
      @shutdown(reason)

  trap_kill: (handler) ->
    @kill_handler = handler

  receive: (pattern, cont) ->
    clause = [pattern, cont]
    if not @clauses
      @clauses = [clause]
    else
      @clauses.push clause

  start: (body) ->
    register_actor @actor_id, this
    setTimeout(@wrap_cont(body, []), 0)

  shutdown: (reason) ->
    @killed = true
    unregister_actor @actor_id
    linked = @linked
    @linked = null
    for actor_id of linked
      actor = lookup_actor(actor_id)
      actor.kill(@actor_id, reason)

  wrap_cont: (cont, args) ->
    actor = this
    -> 
      actor.clauses = null
      return if actor.killed
      reason = null
      current_actor = actor
      try
        cont.apply(actor.state, args)
      catch e
        console.error(String(e))
        actor.clauses = null
        reason = e
      finally
        current_actor = NULL_ACTOR
        if actor.killed
          actor.clauses = null
          return
        if actor.clauses
          actor.mailbox.consumeOnce (message) ->
            for [pattern, cont] in actor.clauses
              captured = WebActors.match(pattern, message)
              if captured
                return actor.wrap_cont(cont, captured)
            return null
        else
          actor.shutdown(reason)
  
next_actor_serial = 0
actors_by_id = {}

alloc_actor_id = ->
  "#{next_actor_serial++}"

lookup_actor = (actor_id) ->
  actors_by_id[actor_id] or new RemoteActor(actor_id)

register_actor = (actor_id, actor) ->
  actors_by_id[actor_id] = actor

unregister_actor = (actor_id) ->
  delete actors_by_id[actor_id]

router_configured = false
get_router = ->
  router = WebActors._router
  if not router_configured
    router.set_default_gateway (actor_id, verb, param) ->
      actor = actors_by_id[actor_id] or new DeadActor(actor_id)
      if verb is "send" or verb is "link" or verb is "unlink"
        actor[verb](param)
      else if verb is "kill"
        [killer_id, reason] = param
        actor.kill(killer_id, reason)
      else
        console.error("Unknown verb '#{verb}' directed at actor #{actor_id}")
    router_configured = true
  router

spawn = (body) ->
  actor_id = alloc_actor_id()
  actor = new LocalActor(actor_id)
  actor.start(body)
  actor_id

spawn_linked = (body) ->
  actor_id = spawn body
  link actor_id
  actor_id

send = (actor_id, message) ->
  actor = lookup_actor(actor_id)
  actor.send(message)

receive = (pattern, cont) ->
  actor = current_actor
  current_actor.receive(pattern, cont)

self = ->
  current_actor.actor_id

send_self = (message) ->
  send current_actor.actor_id, message

trap_kill = (handler) ->
  current_actor.trap_kill handler

kill = (actor_id, reason) ->
  actor = lookup_actor(actor_id)
  actor.kill(current_actor.actor_id, reason)

link = (actor_id) ->
  current_actor.link(actor_id)
  actor = lookup_actor(actor_id)
  actor.link(current_actor.actor_id)

unlink = (actor_id) ->
  current_actor.unlink(actor_id)
  actor = lookup_actor(actor_id)
  actor.unlink(current_actor.actor_id)

sendback = (curried_args...) ->
  actor_id = self()
  (callback_args...) ->
    send actor_id, curried_args.concat(callback_args)

@WebActors.spawn = spawn
@WebActors.spawn_linked = spawn_linked
@WebActors.send = send
@WebActors.receive = receive
@WebActors.self = self
@WebActors.send_self = send_self
@WebActors.trap_kill = trap_kill
@WebActors.kill = kill
@WebActors.link = link
@WebActors.unlink = unlink
@WebActors.sendback = sendback
