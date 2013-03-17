class App
  scope:
    username: null
    email: null
    password: null
    code: null
    sheet:
      collapsed: true
      tab: 'login'
    personas: []
    persona: null
    token: null

  this.$inject = [
    '$compile', '$element', '$http', '$location', '$scope', '$timeout',
    'annotator', 'drafts', 'flash'
  ]
  constructor: (
    $compile, $element, $http, $location, $scope, $timeout
    annotator, drafts, flash
  ) ->
    {plugins, provider} = annotator
    heatmap = annotator.plugins.Heatmap
    dynamicBucket = true

    heatmap.element.bind 'click', =>
      return unless drafts.discard()
      $location.search('id', null).replace()
      dynamicBucket = true
      annotator.showViewer()
      heatmap.publish 'updated'

    heatmap.subscribe 'updated', =>
      elem = d3.select(heatmap.element[0])
      data = {highlights, offset} = elem.datum()
      tabs = elem.selectAll('div').data data
      height = $(window).outerHeight(true)
      pad = height * .2

      {highlights, offset} = elem.datum()

      if dynamicBucket and $location.path() == '/viewer' and annotator.visible
        unless $location.search()?.id
          bottom = offset + heatmap.element.height()
          annotations = highlights.reduce (acc, hl) =>
            if hl.offset.top >= offset and hl.offset.top <= bottom
              if hl.data not in acc
                acc.push hl.data
            acc
          , []
          annotator.showViewer annotations

      elem.selectAll('.heatmap-pointer')
        # Creates highlights corresponding bucket when mouse is hovered
        .on 'mousemove', (bucket) =>
          unless $location.path() == '/viewer' and $location.search()?.id?
            provider.notify
              method: 'setActiveHighlights'
              params: heatmap.buckets[bucket]?.map (a) => a.$$tag

        # Gets rid of them after
        .on 'mouseout', =>
          if $location.path() == '/viewer' and not $location.search()?.id?
            provider.notify method: 'setActiveHighlights'

        # Does one of a few things when a tab is clicked depending on type
        .on 'click', (bucket) =>
          d3.event.stopPropagation()

          # If it's the upper tab, scroll to next bucket above
          if heatmap.isUpper bucket
            threshold = offset + heatmap.index[0]
            next = highlights.reduce (next, hl) ->
              if next < hl.offset.top < threshold then hl.offset.top else next
            , threshold - height
            provider.notify method: 'scrollTop', params: next - pad

          # If it's the lower tab, scroll to next bucket below
          else if heatmap.isLower bucket
            threshold = offset + heatmap.index[0] + pad
            next = highlights.reduce (next, hl) ->
              if threshold < hl.offset.top < next then hl.offset.top else next
            , offset + height
            provider.notify method: 'scrollTop', params: next - pad

          # If it's neither of the above, load the bucket into the viewer
          else
            return unless drafts.discard()
            dynamicBucket = false
            $location.search('id', null)
            annotator.showViewer heatmap.buckets[bucket]

    $scope.submit = (form) ->
      return unless form.$valid
      params = for name, control of form when control.$modelValue?
        [name, control.$modelValue]
      params.push ['__formid__', form.$name]
      data = (((p.map encodeURIComponent).join '=') for p in params).join '&'

      $http.post '', data,
        headers:
          'Content-Type': 'application/x-www-form-urlencoded'
        withCredentials: true
      .success (data) =>
        if data.model? then angular.extend $scope, data.model
        if data.flash? then flash q, msgs for q, msgs of data.flash
        if data.status is 'failure' then flash 'error', data.reason

    $scope.$watch 'personas', (newValue, oldValue) =>
      if newValue?.length
        annotator.element.find('#persona')
          .off('change').on('change', -> $(this).submit())
          .off('click')
        $scope.sheet.collapsed = true
      else
        $scope.persona = null
        $scope.token = null

    $scope.$watch 'persona', (newValue, oldValue) =>
      if oldValue? and not newValue?
        $http.post 'logout', '',
          withCredentials: true
        .success (data) =>
          $scope.$broadcast '$reset'
          if data.model? then angular.extend($scope, data.model)
          if data.flash? then flash q, msgs for q, msgs of data.flash

    $scope.$watch 'token', (newValue, oldValue) =>
      if plugins.Auth?
        plugins.Auth.token = newValue
        plugins.Auth.updateHeaders()

      if newValue?
        if not plugins.Auth?
          annotator.addPlugin 'Auth',
            tokenUrl: $scope.tokenUrl
            token: newValue
        else
          plugins.Auth.setToken(newValue)
        plugins.Auth.withToken plugins.Permissions._setAuthFromToken
      else
        plugins.Permissions.setUser(null)
        delete plugins.Auth
      if annotator.plugins.Store?
        annotator.plugins.Store.annotations = []
        annotator.plugins.Store.pluginInit()

    $scope.$watch 'visible', (newValue) ->
      if newValue then annotator.show() else annotator.hide()

    $scope.$on 'back', ->
      return unless drafts.discard()
      if $location.path() == '/viewer' and $location.search()?.id?
        $location.search('id', null).replace()
      else
        $scope.visible = false

    $scope.$on 'showAuth', (event, show=true) ->
      angular.extend $scope.sheet,
        collapsed: !show
        tab: 'login'

    $scope.$on '$reset', => angular.extend $scope, @scope

    # Fetch the initial model from the server
    $http.get '',
      withCredentials: true
    .success (data) =>
      if data.model? then angular.extend $scope, data.model
      if data.flash? then flash q, msgs for q, msgs of data.flash

    $scope.$broadcast '$reset'

    # Update scope with auto-filled form field values
    $timeout ->
      for i in $element.find('input') when i.value
        $i = angular.element(i)
        $i.triggerHandler('change')
        $i.triggerHandler('input')
    , 200  # We hope this is long enough


class Annotation
  this.$inject = [
    '$element', '$location', '$scope', '$rootScope', '$timeout',
    'annotator', 'drafts'
  ]
  constructor: (
    $element, $location, $scope, $rootScope, $timeout
    annotator, drafts
  ) ->
    publish_ = (args...) ->
      # Publish after a timeout to escape this digest
      # Annotator event callbacks don't expect a digest to be active
      $timeout (-> annotator.publish args...), 0, false

    $scope.privacyLevels = [
     {name: 'Public', permissions:  { 'read': ['group:__world__'] } },
     {name: 'Private', permissions: { 'read': [] } }
    ]

    threading = annotator.threading

    $scope.cancel = ->
      $scope.editing = false
      drafts.remove $scope.$modelValue
      if $scope.unsaved
        publish_ 'annotationDeleted', $scope.$modelValue

    $scope.save = ->
      $scope.editing = false
      $scope.model.$setViewValue $scope.model.$viewValue
      drafts.remove $scope.$modelValue
      if $scope.unsaved
        publish_ 'annotationCreated', $scope.$modelValue
      else
        publish_ 'annotationUpdated', $scope.$modelValue

    $scope.reply = ->
      unless annotator.plugins.Auth? and annotator.plugins.Auth.haveValidToken()
        $rootScope.$broadcast 'showAuth', true
        return

      references =
        if $scope.thread.message.references
          [$scope.thread.message.references, $scope.thread.message.id]
        else
          [$scope.thread.message.id]

      reply = angular.extend annotator.createAnnotation(),
        thread: references.join '/'

    $scope.getPrivacyLevel = (permissions) ->
      for level in $scope.privacyLevels
        roleSet = {}

        # Construct a set (using a key->exist? mapping) of roles for each verb
        for verb of permissions
          roleSet[verb] = {}
          for role in permissions[verb]
            roleSet[verb][role] = true

        # Check that no (verb, role) is missing from the role set
        mismatch = false
        for verb of level.permissions
          for role in level.permissions[verb]
            if roleSet[verb]?[role]?
              delete roleSet[verb][role]
            else
              mismatch = true
              break

          # Check that no extra (verb, role) is missing from the privacy level
          mismatch ||= Object.keys(roleSet[verb]).length
          if mismatch then break else return level

      # Unrecognized privacy level
      name: 'Custom'
      value: permissions

      annotator.setupAnnotation reply

    $scope.$on '$routeChangeStart', -> $scope.cancel() if $scope.editing
    $scope.$on '$routeUpdate', -> $scope.cancel() if $scope.editing

    $scope.$watch 'editing', (newValue) ->
      if newValue then $timeout -> $element.find('textarea').focus()

    # Check if this is a brand new annotation
    if drafts.contains $scope.$modelValue
      $scope.editing = true
      $scope.unsaved = true

    $scope.directChildren = ->
      if $scope.$modelValue? and threading.getContainer($scope.$modelValue.id).children?
        return threading.getContainer($scope.$modelValue.id).children.length
      0

    $scope.allChildren = ->
      if $scope.$modelValue? and threading.getContainer($scope.$modelValue.id).flattenChildren()?
        return threading.getContainer($scope.$modelValue.id).flattenChildren().length
      0

class Editor
  this.$inject = ['$location', '$routeParams', '$scope', 'annotator']
  constructor: ($location, $routeParams, $scope, annotator) ->
    save = ->
      $scope.$apply ->
        $location.path('/viewer').replace()
        annotator.provider.notify method: 'onEditorSubmit'
        annotator.provider.notify method: 'onEditorHide'

    cancel = ->
      $scope.$apply ->
        search = $location.search() or {}
        delete search.id
        $location.path('/viewer').search(search).replace()
        annotator.provider.notify method: 'onEditorHide'

    annotator.subscribe 'annotationCreated', save
    annotator.subscribe 'annotationDeleted', cancel

    $scope.$on '$destroy', ->
      annotator.unsubscribe 'annotationCreated', save
      annotator.unsubscribe 'annotationDeleted', cancel


class Viewer
  this.$inject = [
    '$location', '$routeParams', '$scope',
    'annotator'
  ]
  constructor: (
    $location, $routeParams, $scope,
    annotator
  ) ->
    {plugins, provider} = annotator

    listening = false
    refresh = =>
      return unless annotator.visible
      this.refresh $scope, $routeParams, annotator
      if listening
        if $scope.detail
          plugins.Heatmap.unsubscribe 'updated', refresh
          listening = false
      else
        unless $scope.detail
          plugins.Heatmap.subscribe 'updated', refresh
          listening = true

    $scope.showDetail = (annotation) ->
      search = $location.search() or {}
      search.id = annotation.id
      $location.search(search).replace()

    $scope.focus = (annotation) ->
      if $routeParams.id?
        highlights = [$scope.thread.message.annotation.$$tag]
      else if angular.isArray annotation
        highlights = (a.$$tag for a in annotation when a?)
      else if angular.isObject annotation
        highlights = [annotation.$$tag]
      else
        highlights = []
      provider.notify method: 'setActiveHighlights', params: highlights

    $scope.$on '$destroy', ->
      if listening then plugins.Heatmap.unsubscribe 'updated', refresh

    $scope.$on '$routeUpdate', refresh

    refresh()

  refresh: ($scope, $routeParams, annotator) =>
    if $routeParams.id?
      $scope.detail = true
      $scope.thread = annotator.threading.getContainer $routeParams.id
      $scope.focus $scope.thread.message.annotation
    else
      $scope.detail = false
      $scope.focus []


angular.module('h.controllers', [])
  .controller('AppController', App)
  .controller('AnnotationController', Annotation)
  .controller('EditorController', Editor)
  .controller('ViewerController', Viewer)
