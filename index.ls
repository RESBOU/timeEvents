# autocompile

# * require
require! {
  bluebird: p
  leshdash: { w, find, omit, filter, pick, keys, values, pop, assign, each, reduce, flattenDeep, push, map, mapValues, omit }  
  moment
  'moment-range'
}

# * Type coercion functions for a more chilled out API
format = exports.format = -> it.format 'YYYY-MM-DD'

exports.moment = moment

parse = exports.parse = do
  pattern: ->
    | it?isEvent? => [ it.range!, payload: it.payload ]
    | it?@@ is Object and it.range? => [ parse.range(it.range), omit(it, 'range') ]
    | it?@@ is Object => [ false, it ]
    | otherwise => throw new Error "invalid type for patern #{it?toString?!} #{it?@@}"
    
  # (any) -> Event | Error
  event: ->
    if it?isEvent? then return it
    switch it?@@
      | Object => new Event it
      | otherwise =>
        console.log it
        console.log String it
        throw new Error "invalid type for event #{it?toString?!} #{it?@@}"

  # (any) -> MemEvents | Error
  events: ->
    if it?isEvents? then return it
      
    switch it?@@
      | Array => new MemEvents it
      | otherwise => new MemEvents parse.event it

  # (Any) -> Array<Event> | Error
  eventArray: ->
    if it?isEvents? then return it.toArray()
    flattenDeep switch it?@@
      | Array => map it, parse.eventArray
      | otherwise => [ parse.event it ]
        
  # ( Events | Event | void ) -> Range
  range: (something, def) ->
    if something?isEvent? or something?isEvents? then return something.range!
      
    switch something?@@
      | false => def or void
      | Object => moment.range something
      | Array => moment.range something
      | otherwise => something.range?! or something
    
# ( Events | Array<Event> | Event | void ) -> Array<Event>
  eventCollection: (something) ->
    if something?isEvent? then return [ something ]
    if something?isEvents? then return something.toArray!
    
    switch something?@@
      | void => []
      | Array => flattenDeep something
      | otherwise => throw 'what is this'

Matcher = (range, pattern, event) -->
  
#  console.log "MATCHER PATTERH", range: range.toDate!, pattern: pattern, event: event.range!toDate!

  checkRange = (event) ->
    if range
      res = range.contains event.start.clone().add(1) or range.contains event.end.clone().subtract(1) or event.range!contains range
      return res
    else return true

  checkRangeStrict = (event) -> range.isEqual event.range!

  checkPattern = (event) ->
    not find pattern, (value, key) ->
      switch value?@@
        | undefined => true
        
        | Boolean =>
          if value then not event[key]?
          else event[key]?
          
        | Function => not value event[key]

        | otherwise =>
          if moment.isMoment value then not value.isSame event[key]
          else if event[key] is value then false else true

  checkRange(event) and checkPattern(event)


# * EventLike
# more of a spec then anything, this is implemented by Event & Events

EventLike = exports.EventLike = class EventLike

  # fetches all events from a collection relevant to current event (by type and range)
  # ( Events ) -> Events
  relevantEvents: (events) ->
    parse.events events
    .filter range: @range(), type: @type

  neighbours: (events) ->
    [
      events.filter end: @start.clone()
      events.filter start: @end.clone()
    ]

  # get or set range
  # (range?) -> moment.range
  range: (setRange) ->
    if range = setRange
      @start = range.start.clone()
      @end = range.end.clone()
    else
      range = new moment.range @start, @end
      
    range

  # ( EventLike ) -> Events
  push: (event) -> ...
    
  # ( EventLike ) -> Events
  subtract: (something) ->
    if something instanceof Events then @subtractMany something
    else @subtractOne something
    
  # ( EventLike, (Event, Event) -> Events) -> Events
  collide: (events, cb) -> ...

  each: -> ...

  subtractMany: -> ...

  subtractOne: -> ...

# * Event
# represents some event in time, defined by start and end timestamps
# caries some payload, like a price or a booking

parseInit = (data) ->
  if not data then return {}
  if data@@ isnt Object then return "wut wut"
  data = {} <<< data
    
  if data.center then return { start: moment.utc data.start, end: moment.utc data.end }
    
  if data.range
    data.start = data.range.start
    data.end = data.range.end
    delete data.range
  
  if data.start?@@ in [ Date, String ] then data.start = moment.utc data.start

  if data.end?@@ in [ Date, String ] then data.end = moment.utc data.end

  if not data.id then data.id = data.start.format() + " " + data.end.format() + " " + data.type
        
  return data

Event = exports.Event = class Event extends EventLike
  isEvent: true
  
  (init) -> assign @, parseInit init

  compare: (event) ->
    [ @isSameRange(event), @isSamePayload(event) ]

  isSame: (event) ->
    @isSameRange(event) and @isSamePayload(event)

  isSameRange: (event) ->
    event = parse.event event
    @range!isSame event.range!
    
  isSamePayload: (event) ->
    event = parse.event event
    (@type is event.type) and (@payload is event.payload)
  
  clone: (data={}) ->
    ret = new Event assign {}, @, { id: @id + '-clone'}, data
    delete ret.repr
    ret

  # () -> Json
  serialize: ->
    pick(@, <[type payload id tags]>) <<< mapValues (pick @, <[ start end ]>), (value) -> value.utc().format()

  # () -> String
  toString: ->
    start = format @start
    end = format @end
    if @price then "Price(" + @price + " " + start + ")"
    else "Event(" + (@id or "unsaved-" + @type)  + ")"
    
  # ( Events ) -> Events
  subtractMany: (events) ->
    @relevantEvents events
    .reduce do
      (res, event) ~> res.subtractOne event
      new MemEvents @
      
  # ( Event ) -> Events
  subtractOne: (event) ->
    cnt = 0
    range = event.range()
    range.start.subtract 1, 'second'
    range.end.add 1 'second'
    
    new MemEvents map do
      @range().subtract range
      ~> @clone { start: it.start, end: it.end, id: @id + '-' + cnt++ } # get rid of potential old repr, this is a new event
      
  # ( Events, (Event, Event) -> Events ) -> Events
  collide: (events, cb) ->
    @relevantEvents events
    .reduce (events, event) ~> events.pushm cb event, @

  each: (cb) -> cb @
    
  merge: (event) ->
    newSelf = @clone()
    if event.start < newSelf.start then newSelf.start = event.start
    if event.end > newSelf.end then newSelf.end = event.end
    newSelf
    

PersistLayer = exports.PersistLayer = class
  markRemove: -> @toRemove = true
  
  save: -> new p (resolve,reject) ~>
    if @toRemove then resolve @remove!
    else ...
      
  remove: -> new p (resolve,reject) ~> ...

# * Events
# abstract event collection
# supporting common set operations,
# and some uncommon operations related to time (collide, subtract)
 
Events = exports.Events = class Events extends EventLike
  (...events) -> @pushm.apply @, events

  # per day data (airbnb api helper)
  days: (cb) -> @each (event) -> event.range!by 'days', ~> cb it, event

  isEvents: true

  # ( MomentRange, Object ) -> Events
  find: (range, pattern) -> ...
    
  # ( rangeEquivalent ) -> Events
#  clone: (rangeEquivalent) ~> ...

  # ( EventCollection) -> Events
  pushm: (eventCollection) -> ...

  # ( EventCollection) -> Events
  push: (eventCollection) -> @clone eventCollection

  # () -> Events
  without: ->  ...

  # ( Function ) -> void
  each: (cb) -> ...

  # () -> String
  toString: -> "E[#{@length}] < " + (@map (event) -> "" + event).join(", ") + " >"

  # () -> Json
  serialize: -> @map (.serialize!)

  # () -> Array<Event>
  toArray: ->
    ret = []
    @each -> ret.push it
    ret

  # ( (Event) -> any) ) -> Array<any>
  map: (cb) ->
    ret = []
    @each (event) -> ret.push cb event
    ret

  # () -> Object
  summary: ->
    @rawReduce (stats, event) -> (stats or {}) <<< "#{event.type}": (stats?[event.type] or 0) + 1
  
  # ( (Events, Event) -> Events ) -> Array<any>
  rawReduce: (cb, memo) ->
    @each (event) -> memo := cb memo, event
    memo
    
  # ( (Events, Event) -> Events ) -> Events
  reduce: (cb, memo) ->
    if not memo then memo = new MemEvents()
    @rawReduce cb, memo

  # ( Event ) -> Boolean
  has: (targetEvent) ->
    range = targetEvent.range!
    @_find (event) -> event.payload is targetEvent.payload and event.range!isSame range
            
  # ( Event | { range: Range, ... } ) -> Events
  find: ->
    matcher = Matcher.apply @, parse.pattern it
    @_find matcher
    
  # ( { range: Range, ... } ) -> Events
  filter: ( pattern )->
    matcher = Matcher.apply @, parse.pattern pattern
    @reduce (ret, event) -> if matcher event then ret.pushm event else ret
    
  diff: (events) ->
    makeDiff = (diff, event) ~>
      collisions = event.relevantEvents diff
      if not collisions.length then return diff
      else
        return diff.popm(collisions).pushm collisions.reduce (res, collision) ->
          
          [ range, payload ] = event.compare collision
          
          if not range and not payload then return res.pushm collision
          if payload then return res.pushm collision.subtract event
          if range then return res.pushm collision
          return res

    events = parse.events events
    @reduce makeDiff, events.clone()

  # complately transforms the group of events, returning ranges added and removed, and db events to delete and create to apply the change
  # ( Events ) -> { busy: Events, free: Events, create: Events, remove: Events }
  change: (newEvents) ->
    newEvents = parse.events newEvents
    busy = newEvents.subtract @
    free = @subtract newEvents

    create = newEvents.reduce (create, event) ~> if not @has event then create.pushm event else create
    remove = @reduce (remove, event) -> if not newEvents.has event then remove.pushm event else remove
        
    busy: busy, free: free, create: create, remove: remove

  # upates events
  # ( Events ) -> Events
  update: (events) ->
    @reduce do
      ([ create, remove ], event) ~>

        if (relevantEvents = event.relevantEvents(events)).length
          remove.pushm event
          create.pushm event.subtract relevantEvents

        [ create, remove ]

      [ events.clone(), new MemEvents() ]
            
  merge: ->
    @reduce (res, event) ~>
      event
      .neighbours(@)
      .map (oldEvent) -> 
        if oldEvent.length and oldEvent.payload is oldEvent.payload then oldEvent.merge event
    
  # ( Events ) -> Events
  union: (events) ->
    res = @clone()
    events.each ~> res.pushm it
    res

  # ( (Events, (Event1, Event2) -> Events ) -> Events
  collide: (events, cb) ->
    @reduce (memo, event) -> memo.pushm event.collide events, cb

  # ( Event ) -> Events
  subtractOne: (event) ->
    @reduce (ret, child) -> ret.pushm child.subtract event

  # ( Events ) -> Events
  subtractMany: (events) ->
    @reduce (ret, child) -> ret.pushm child.subtractMany events

# * MemEvents
# In memory Event collection implementation,
# this is a very naive implementation
# 
# I guess we should use range tree data structure or something smart like that for fast range search in the future.
# its good enough for now even if we end up quadratic complexity for algos, we are not parsing many events per property.
# 
MemEvents = exports.MemEvents = class MemEventsNaive extends Events
  ->
    assign @, do
      events:  {}
      length: 0
      type: {}
    super ...
  
  without: (event) -> new MemEvents filter (values @events), -> it.id isnt event.id
    
  toArray: -> values @events

  each: (cb) -> each @events, cb
  
  _find: (cb) -> find @events, cb

  clone: (range) -> new MemEvents values @events

  popm: (...events) -> 
    each parse.eventArray(events), (event) ~>
      if not event then return
      if not @events[event.id]? then return
      else
        delete @events[event.id]
        @length--
    @

  pushm: (...events) ->
    each parse.eventArray(events), (event) ~>
      if not event then return
      if @events[event.id]? then return
      @events[event.id] = event
      @type[event.type] = true

      if event.start < @start or not @start then @start = event.start
      if event.end < @end or not @end then @end = event.end
      
      @length++
    @
  
