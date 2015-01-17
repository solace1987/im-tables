_ = require 'underscore'
{Promise} = require 'es6-promise'

# Base class
Modal = require './modal'

# Text strings
Messages = require '../messages'
# Configuration
Options = require '../options'
# Templating
Templates = require '../templates'
# The model for this class.
CodeGenModel = require '../models/code-gen'
# The checkbox sub-component.
Checkbox = require '../core/checkbox'
# This class uses the code-gen message bundle.
require '../messages/code-gen'
# We use this xml indenter
indentXml = require '../utils/indent-xml'
# We use this string compacter.
stripExtraneousWhiteSpace = require '../utils/strip-extra-whitespace'
# We need access to a cdn resource - google's prettify
withResource = require '../utils/with-cdn-resource'

# Comment finding regexen
OCTOTHORPE_COMMENTS = /\s*#.*$/gm
C_STYLE_COMMENTS = /\/\*(\*(?!\/)|[^*])*\*\//gm # just strip blocks.
XML_MIMETYPE = 'application/xml;charset=utf8'
CANNOT_SAVE = {level: 'Info', key: 'codegen.CannotExportXML'}

withPrettyPrintOne = _.partial withResource, 'prettify', 'prettyPrintOne'

withFileSaver = _.partial withResource, 'filesaver', 'saveAs'

alreadyRejected = Promise.reject 'Requirements not met'

canSaveFromMemory = ->
  if not 'Blob' in global
    alreadyRejected
  else
    withFileSaver _.identity

module.exports = class CodeGenDialogue extends Modal

  # Connect this view with its model.
  Model: CodeGenModel

  # We need a query, and we need to start generating our code.
  initialize: ({@query}) ->
    super
    @generateCode()
    @setExportLink()

  # The static descriptive stuff.

  modalSize: -> 'lg'

  title: -> Messages.getText 'codegen.DialogueTitle', query: @query, lang: @model.get('lang')

  primaryIcon: -> 'Download'

  primaryAction: -> Messages.getText 'codegen.PrimaryAction'

  body: Templates.template 'code_gen_body'

  # Conditions which must be true on instantiation

  invariants: ->
    hasQuery: "No query"

  hasQuery: -> @query?

  # Recalulate the code if the lang changes, otherwise just re-present it.
  modelEvents: ->
    'change:lang': @onChangeLang
    'change:showBoilerPlate': @reRenderBody
    'change:highlightSyntax': @reRenderBody

  # Show the code if it changes.
  stateEvents: -> 'change:generatedCode': @reRenderBody

  # The DOM events - setting the attributes of the model.
  events: -> _.extend super,
    'click .dropdown-menu.im-code-gen-langs li': 'chooseLang'

  # Get a regular expression that will strip comments.
  getBoilerPlateRegex: ->
    return if @model.get 'showBoilerPlate'
    switch @model.get 'lang'
      when 'pl', 'py', 'rb' then OCTOTHORPE_COMMENTS
      when 'java' then C_STYLE_COMMENTS
      else null

  act: -> # only called for XML data, and only in supported browsers.
    blob = new Blob [@state.get('generatedCode')], type: XML_MIMETYPE
    saveAs blob, "#{ @query.name ? 'name' }.xml"

  onChangeLang: ->
    lang = @model.get 'lang'
    @$('.im-current-lang').text Messages.getText 'codegen.Lang', {lang}
    @$('.modal-title').text @title()
    if lang is 'xml'
      canSaveFromMemory().then => @state.unset 'error'
                         .then null, => @state.set error: CANNOT_SAVE
    else
      @state.unset 'error'
    @generateCode()
    @setExportLink()

  generateCode: ->
    lang = @model.get 'lang'
    switch lang
      when 'xml' then @state.set generatedCode: indentXml @query.toXML()
      else @query.fetchCode(lang).then (code) => @state.set generatedCode: code

  setExportLink: ->
    lang = @model.get 'lang'
    switch lang
      when 'xml' then @state.set exportLink: null
      else @state.set exportLink: @query.getCodeURI lang

  # This could potentially go into Modal, but it would need more stuff
  # to make it generic (dealing with children, etc). Not worth it for
  # such a simple method.
  reRenderBody: -> if @rendered
    # Replace the body with the current state of the body.
    @$('.modal-body').html @body @getData()
    # Trigger any DOM modifications, also re-renders the footer.
    @trigger 'rendered', @rendered

  postRender: ->
    super
    @addCheckboxes()
    @highlightCode()

  addCheckboxes: ->
    @renderChildAt '.im-show-boilerplate', new Checkbox
      model: @model
      attr: 'showBoilerPlate'
      label: 'codegen.ShowBoilerPlate'
    @renderChildAt '.im-highlight-syntax', new Checkbox
      model: @model
      attr: 'highlightSyntax'
      label: 'codegen.HighlightSyntax'

  highlightCode: -> if @model.get 'highlightSyntax'
    lang = @model.get 'lang'
    pre = @$ '.im-generated-code'
    code = @getCode()
    return unless code?
    withPrettyPrintOne (prettyPrintOne) -> pre.html prettyPrintOne _.escape code

  getData: -> _.extend super, options: Options.get('CodeGen'), generatedCode: @getCode()

  getCode: ->
    code = @state.get 'generatedCode'
    regex = @getBoilerPlateRegex()
    return code unless regex
    stripExtraneousWhiteSpace code?.replace regex, ''

  # Information flow from DOM -> Model

  toggleShowBoilerPlate: -> @model.toggle 'showBoilerPlate'

  toggleHighlightSyntax: -> @model.toggle 'highlightSyntax'

  chooseLang: (e) ->
    e.stopPropagation()
    lang = @$(e.target).closest('li').data 'lang'
    @model.set lang: lang

