" Copyright 2020 Google Inc. All rights reserved.
"
" Licensed under the Apache License, Version 2.0 (the "License");
" you may not use this file except in compliance with the License.
" You may obtain a copy of the License at
"
"     http://www.apache.org/licenses/LICENSE-2.0
"
" Unless required by applicable law or agreed to in writing, software
" distributed under the License is distributed on an "AS IS" BASIS,
" WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
" See the License for the specific language governing permissions and
" limitations under the License.

if !exists('s:selectors_by_buffer_number')
  let s:selectors_by_buffer_number = {}
endif


""
" @dict Selector
" Representation of a set of lines for a user to select from, e.g. list of files.
" It can be created with @function(#Create), configured with syntax
" highlighting, key mappings, etc. and shown as a vim window.
"
" The Selector dict has the following options:
"


""
" @public
" Creates a @dict(Selector) from {lines} that can be configured with 
" an optional [options] object and then displayed with Show()
"
" Simple Example:
" >
"   call maktaba#ui#selector#Create(['foo', 'bar']).Show()
" <
"
" {lines} is intended to be a list of lines to display. It should have one
" of three formats:
" - A raw string.
" - A list of strings
" - A list of lists, which each sublist is a tuple of `[LINE, DATA]`, which
"   can be useful if you want each line to correspond to some hidden lines.
"
" Support values for [options]
" * 'mapping': dict of custom keymappings to provide for the selector
"   window. Each entry must have the format: >
"     'key_to_press': {
"         'action': ActionFunction({line}, [datum]),
"         'window': 'SelectorWindowAction', (one of NoOp, Close, Return)
"         'description: 'Help Text'
"     }
"   <
" * 'title': Title of the window. By default, '__SelectorWindow__'
function! maktaba#ui#selector#Create(lines, ...) abort
  let l:options = (a:0 >= 1 && a:1 isnot -1) ?
      \ maktaba#ensure#IsDict(a:1) : {}
  let l:selector = s:DefaultSelectorOptions()
  " Set the input lines; they will be validated later in
  " s:MergeAndProcessOptions.
  let l:selector['lines'] = a:lines

  " Merge and validate options from the user. Also set up the keymappings.
  call s:MergeAndProcessOptions(l:selector, l:options)
  return l:selector
endfunction


" Comment out lines -- used in creating help text
function! s:CommentLines(str)
  let l:out = []
  for l:comment_lines in split(a:str, '\n')
    if l:comment_lines[0] ==# '"'
      call add(l:out, l:comment_lines)
    else
      call add(l:out, '" ' . l:comment_lines)
    endif
  endfor
  return l:out
endfunction


""
" @dict Selector.WithOptions
"
" Process options passed in by the user and set defaults accordingly. The
" following options are available to be set:
function! maktaba#ui#selector#DoWithOptions(options) dict abort
  call s:MergeAndProcessOptions(self, a:options)
  return self
endfunction


""
" @dict Selector.WithMappings
" Set {keymappings} to use in the selector window. Must have the form: >
"   'keyToPress': {
"       'action': ActionFunction({line}, [datum]),
"       'window': 'SelectorWindowAction', (one of NoOp, Close, Return)
"       'description: 'Help Text'
"   }
" <
" Where the "ActionFunction" is the name of a function you specify, which
" takes one or two arguments:
"   1. line: The contents of the line on which the "keyToPress" was pressed.
"   2. datum: data associated with the line when selector was created, if line
"      was initialized as a 2-item list.
"
" And where the "SelectorWindowAction" must be one of the following:
"  - "Close" -- close the SelectorWindow before completing the action
"  - "Return" -- Return to previous window and keep the Selector Window open
"  - "NoOp" -- Perform no action (keeping the SelectorWindow open).
function! maktaba#ui#selector#DoWithMappings(keymappings) dict abort
  let l:custom_mappings = maktaba#ensure#IsDict(a:keymappings)
  let l:mappings = extend(
      \ s:GetDefaultKeyMappings(), l:custom_mappings, 'force')
  let self._mappings = s:ExpandedKeyMappings(l:mappings)
  return self
endfunction


""
" @dict Selector.Show
" Shows a selector window for the @dict(Selector) with [minheight], [maxheight],
" and [position].
" @default minheight=5
" @default maxheight=25
" @default position='botright'
function! maktaba#ui#selector#DoShow() dict abort
  let l:min_win_height = self.minheight
  let l:max_win_height = self.maxheight
  let l:position = self.position

  " Show one empty line at the bottom of the window.
  " (2 is correct -- I know it looks bizarre)
  let l:win_size = len(self._infolist) + 2
  if l:win_size > l:max_win_height
    let l:win_size = l:max_win_height
  elseif l:win_size < l:min_win_height
    let l:win_size = l:min_win_height
  endif

  let s:current_savedview = winsaveview()
  let s:curpos_holder = getpos(".")
  let s:last_winnum = winnr()

  " Open the window in the specified window position.  Typically, this opens
  " up a flat window on the bottom (as with split).
  execute l:position l:win_size 'new'
  let s:selectors_by_buffer_number[bufnr('%')] = self
  call s:SetWindowOptions(self)
  silent execute 'file' self.title
  let l:lines = self._infolist.lines
  let l:data = self._infolist.data

  let b:selector_lines_data = l:data
  call s:InstantiateKeyMaps(self._mappings)
  setlocal noreadonly
  setlocal modifiable
  call maktaba#buffer#Overwrite(1, line('$'), l:lines)
  " Add the help comments at the top (do this last so cursor stays below it).
  call append(0, self._GetHelpLines())
  setlocal readonly
  setlocal nomodifiable

  " Restore the previous windows view
  let l:buffer_window = winnr()
  call maktaba#ui#selector#ReturnToWindow()
  call winrestview(s:current_savedview)
  execute l:buffer_window  'wincmd w'

  return self
endfunction


""
" @private
" Gets data associated with {lineno}, as passed in 2-item form of infolist when
" creating a selector with @function(#Create).
" @throws NotFound if no data was configured for requested line.
function! maktaba#ui#selector#DoGetLineData(lineno) dict abort
  let l:lineno = a:lineno - len(self._GetHelpLines())
  if has_key(b:selector_lines_data, l:lineno)
    return b:selector_lines_data[l:lineno]
  endif
  throw maktaba#error#NotFound('Associated data for selector line %d', l:lineno)
endfunction


""
" @private
" Get a list of header lines for the selector window that will be displayed as
" comments at the top. Documents all key mappings if `self.verbose` is 1,
" otherwise just documents that H toggles help.
function! maktaba#ui#selector#DoGetHelpLines() dict abort
  if self._show_verbose_help
    " Map from comments to keys.
    let l:comments_keys = {}
    for l:items in values(self._mappings)
      let l:keycomment = l:items[2]
      let l:key = l:items[3]
      if has_key(l:comments_keys, l:keycomment)
        let l:comments_keys[l:keycomment] = l:comments_keys[l:keycomment]
            \ . ',' . l:key
      else
        let l:comments_keys[l:keycomment] = l:key
      endif
    endfor

    " Map from keys to comments.
    let l:keys_comments = {}
    for l:line_comment in keys(l:comments_keys)
      let l:key = l:comments_keys[l:line_comment]
      let l:keys_comments[key] = l:line_comment
    endfor

    let l:lines = []
    for l:key in sort(keys(l:keys_comments))
      call extend(l:lines,
          \ s:CommentLines(printf('%s\t: %s', l:key, l:keys_comments[l:key])))
    endfor
    return l:lines
  else
    return s:CommentLines("Press 'H' for more options.")
  endif
endfunction


""
" @private
function! maktaba#ui#selector#ToggleCurrentHelp(...) abort
  let l:selector = s:selectors_by_buffer_number[bufnr('%')]
  call l:selector.ToggleHelp()
endfunction


""
" @dict Selector.ToggleHelp
" Toggle whether verbose help is shown for the selector.
function! maktaba#ui#selector#DoToggleHelp() dict abort
  " TODO(dbarnett): Don't modify buffer if none exists.
  let l:prev_read = &readonly
  let l:prev_mod = &modifiable
  setlocal noreadonly
  setlocal modifiable
  let l:len_help = len(self._GetHelpLines())
  let self._show_verbose_help = !self._show_verbose_help
  call maktaba#buffer#Overwrite(1, l:len_help, self._GetHelpLines())
  let &readonly = l:prev_read
  let &modifiable = l:prev_mod
endfunction


" Initialize the key bindings
function! s:InstantiateKeyMaps(mappings) abort
  for l:scrubbed_key in keys(a:mappings)
    let l:items = a:mappings[l:scrubbed_key]
    let l:actual_key = l:items[3]
    let l:mapping = 'nnoremap <buffer> <silent> ' . l:actual_key
        \ . " :call maktaba#ui#selector#KeyCall('" . l:scrubbed_key . "')<CR>"
    execute l:mapping
  endfor
endfunction


""
" @private
" Perform the key action.
"
" The {scrubbed_key} allows us to retrieve the original key.
function! maktaba#ui#selector#KeyCall(scrubbed_key) abort
  let l:selector = s:selectors_by_buffer_number[bufnr('%')]
  let l:contents = getline('.')
  let l:action_func = l:selector._mappings[a:scrubbed_key][0]
  let l:window_func = l:selector._mappings[a:scrubbed_key][1]
  if l:contents[0] ==# '"' &&
      \ a:scrubbed_key !=# s:QUIT_KEY
      \ && a:scrubbed_key !=# s:HELP_KEY
    return
  endif
  try
    let l:datum = l:selector._GetLineData(line('.'))
  catch /ERROR(NotFound):/
    " No data associated with line. Ignore and leave l:datum undefined.
  endtry
  call maktaba#function#Call(l:window_func)
  if exists('l:datum')
    call maktaba#function#Call(l:action_func, [l:contents, l:datum])
  else
    call maktaba#function#Call(l:action_func, [l:contents])
  endif
endfunction


""
" @private
" Internal syntax used for the help text in the selector window.
function! maktaba#ui#selector#DoHelpTextSyntax() dict abort
  syntax region SelectorComment start='^"' end='$'
      \ contains=SelectorKey,SelectorKey2,SelectorKey3
  syntax match SelectorKey "'<\?\w*>\?'" contained
  syntax match SelectorKey2 '<\w*>\t:\@=' contained
  syntax match SelectorKey3
      \ '\(\w\|<\|>\)\+\(,\(\w\|<\|>\)\+\)*\t:\@=' contained
  highlight default link SelectorComment Comment
  highlight default link SelectorKey Keyword
  highlight default link SelectorKey2 Keyword
  highlight default link SelectorKey3 Keyword
endfunction


"-------------------------
" Options processing code
"-------------------------

" Get the default selector options. This is essentially the constructor for
" the selector.
function! s:DefaultSelectorOptions() abort
  let l:default_mappings = s:DefaultKeyMappings()
  let l:system_key_mappings = s:SystemDefaultKeyMappings()
  let l:default_window_options = s:DefaultWindowOptions()

  " Create a selector object width the relevant defaults
  "
  " For readability of this code:
  " - User-provided options should go first
  " - public methods should follow.
  " - private lines and private methods should go second, prefixed by _
  let l:selector = {
    \ 'lines': [],
    \
    \ 'title': '__SelectorWindow__',
    \ 'minheight': 5,
    \ 'maxheight': 25,
    \ 'cursorline': 1,
    \ 'pos': 'botright',
    \ 'filetype': 'selectorwindow',
    \ 'custom_syntax': {
    \   'syntax': [],
    \   'highlight': [],
    \ },
    \ 'mapping': l:default_mappings,
    \ 'postdisplay_callback': function('maktaba#ui#selector#NoOp'),
    \
    \ 'WithOptions': function('maktaba#ui#selector#DoWithOptions'),
    \ 'Show': function('maktaba#ui#selector#DoShow'),
    \ 'ToggleHelp': function('maktaba#ui#selector#DoToggleHelp'),
    \
    \ '_window_options': l:default_window_options,
    \ '_system_key_mappings': l:system_key_mappings,
    \ '_show_verbose_help': 0,
    \ '_processed_key_mappings': {},
    \ '_processed_lines': {},
    \ '_HelpTextSyntax': function('maktaba#ui#selector#DoHelpTextSyntax'),
    \ '_GetHelpLines': function('maktaba#ui#selector#DoGetHelpLines'),
    \ '_GetLineData': function('maktaba#ui#selector#DoGetLineData'),
  \ }
  return l:selector
endfunction

" Take options from the user and merge them into an existing selector object.
function! s:MergeAndProcessOptions(selector, options) abort
  let l:selector = maktaba#ensure#IsDict(a:selector)
          let l:options = maktaba#ensure#IsDict(a:options)

  let l:selector['_processed_data'] = s:ProcessLines(l:selector['lines'])

  " Key-to-function map, where the key indicates how the key should be
  " processed. There are two options for functions:
  " - 'process': Function of the form fn(option_value) that validates a value
  "   and which just overwrites the old value.
  " - 'processComplex': Function of the form fn(existing_value, new_value)
  "   that allows for more complex merging logic.
  let l:process_options = {
    \ 'title': function('maktaba#ui#selector#ProcessTitleOpt'),
    \ 'minheight': function('maktaba#ui#selector#ProcessMinHeightOpt'),
    \ 'maxheight': function('maktaba#ui#selector#ProcessMaxHeightOpt'),
    \ 'cursorline': function('maktaba#ui#selector#ProcessCursorlineOpt'),
    \ 'pos': function('maktaba#ui#selector#ProcessPosOpt'),
    \ 'filetype': function('maktaba#ui#selector#ProcessFiletypeOpt'),
    \ 'custom_syntax': function('maktaba#ui#selector#ProcessCustomSyntaxOpt'),
    \ 'mapping': function('maktaba#ui#selector#ProcessKeyMappingsOpt'),
    \ 'postdisplay_callback': function('maktaba#ui#selector#ProcessCallbackOpt'),
  \ }

  for l:key in keys(l:options)
    if !has_key(l:process_options, l:key)
      throw maktaba#error#BadValue(
        \ 'SelectorWindow option "%s" unknown. ' .
        \ ' Available options are %s', l:key, sort(keys(l:process_options)))
    endif
  endfor

  for l:key in keys(l:process_options)
    if has_key(l:options, l:key)
      if !has_key(l:selector, l:key)
        " This would be a programming error on the part of the maktaba
        " authors. Oops.
        throw maktaba#error#Failure('Key %s not in selector options', l:key)
      endif
      let l:selector[l:key] = l:process_options[l:key](
          \ l:key, l:options[l:key], l:selector[l:key])
    endif
  endfor

  return l:selector
endfunction


""
" @private
" Process the title option
function! maktaba#ui#selector#ProcessTitleOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsString(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'string, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process the min height option
function! maktaba#ui#selector#ProcessMinHeightOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsNumber(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'number, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process the max height option
function! maktaba#ui#selector#ProcessMaxHeightOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsNumber(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'number, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process the cursorline option
function! maktaba#ui#selector#ProcessCursorlineOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsBool(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'bool, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process the split option
function! maktaba#ui#selector#ProcessPosOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsString(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'string, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process the filetype option
function! maktaba#ui#selector#ProcessFiletypeOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsString(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'string, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction


""
" @private
" Process custom syntax options
function! maktaba#ui#selector#ProcessCustomSyntaxOpt(key, opt_val,sel_val) abort
  let l:ov = maktaba#ensure#IsDict(a:opt_val)
  let l:out = {
    \ 'syntax': [],
    \ 'highlight': [],
  \ }
  for l:key in keys(l:ov)
    if l:key != 'syntax' && l:key != 'highlight'
      throw maktaba#error#BadValue(
        \ 'For %s option, got unknown key "%s"; ' .
        \ 'only possible keys are "syntax" and "highlight"', a:key, l:key)
    endif
  endfor
  if has_key(l:ov, 'syntax')
    let l:out['syntax'] = maktaba#ensure#IsList(l:ov['syntax'])
  endif
  if has_key(l:ov, 'highlight')
    let l:out['highlight'] = maktaba#ensure#IsList(l:ov['highlight'])
  endif
  return l:out
endfunction


""
" @private
"
" Process custom key mappings. Should be a Dict of Dicts, where each key in
" the parent dict should look like:
"
" >
"   'key_to_press': {
"       'action': ActionFunction({line}, [datum]),
"       'window': '<SelectorWindowAction>', (one of NoOp, Close, Return)
"       'description: 'Help Text'
"   }
" <
"
" An empty object will remove a key:
"
" >
"   'key_to_remove': {}
" <
function! maktaba#ui#selector#ProcessKeyMappingsOpt(key, opt_val, sel_val) abort
  let l:sv = maktaba#ensure#IsDict(a:sel_val)
  let l:ov = maktaba#ensure#IsDict(a:opt_val)
  let l:out = {}
  for l:key in keys(l:sv)
    let l:out[l:key] = l:sv[l:key]
  endfor
  for l:key in keys(l:ov)
    let l:key_obj = l:ov[l:key]
    if len(l:key_obj) == 0
      " Special case: Remove the key object.
      if has_key(l:out, l:key)
        call remove(l:out, l:key)
      endif
      continue
    endif

    call maktaba#ensure#IsFuncref(l:key_obj['action'])
    let l:window = l:key_obj['window']
    if !has_key(s:window_action_mapping, l:window)
      call maktaba#error#BadValue('For key %s, got window action ' .
        \ '%s, but most be one of Close, Return, NoOp', l:key, l:window)
    endif
    call maktaba#ensure#IsString(l:key_obj['description'])
    let l:out[l:key] = l:key_obj
  endfor
  return l:out
endfunction


""
" @private
" Process the postdisplay callback option
function! maktaba#ui#selector#ProcessCallbackOpt(key, opt_val, sel_val) abort
  if !maktaba#value#IsFuncref(a:opt_val)
    throw maktaba#error#WrongType('Selector option key %s should be a '
        \ . 'function, but was %s', a:key, a:opt_val)
  endif
  return a:opt_val
endfunction



" Available options for the 'window' option in a key mapping.
let s:window_action_mapping = {
\ 'Close' : function('maktaba#ui#selector#CloseWindow'),
\ 'Return' : function('maktaba#ui#selector#ReturnToWindow'),
\ 'NoOp'  : function('maktaba#ui#selector#NoOp'),
\ }


" Create the full key mappings dict.
function! s:ExpandedKeyMappings(mappings) abort
  " A map from the key (scrubbed of <>s) to:
  "   - The main action
  "   - the window action
  "   - the help item
  "   - the actual key press (with the brackets)
  let l:expanded_mappings = {}
  for l:keypress in keys(a:mappings)
    let l:items = a:mappings[l:keypress]
    " Check if the keypress is just left or right pointies (<>)
    let l:scrubbed = l:keypress
    if l:keypress =~# '\m<\|>'
      " Left and right pointies must be scrubbed -- they have special meaning
      " when used in the context of creating key mappings, which is where the
      " scrubbed keypresses are used.
      let l:scrubbed = substitute(substitute(l:keypress, '<', '_Gr', 'g'),
          \ '>', '_Ls', 'g')
    endif
    let l:window_action = get(s:WindowActionMapping,
        \ l:items[1], l:items[1])
    let l:expanded_mappings[l:scrubbed] =
        \ [l:items[0], l:window_action, l:items[2], l:keypress]
  endfor
  return l:expanded_mappings
endfunction


" Processes {lines}, which has the following formats:
" * A raw string
" * A list of strings
" * A list of lists, where the sub-list should be a tuple having the format of
"   (string, data)
"
" Returns a dict with two fields:
" - lines: list of string data to display
" - data: dict, keyed by line number, with the value being some arbitrary
"   data to associate with that line number.
function! s:ProcessLines(lines) abort
  let l:info = a:lines
  if maktaba#value#IsString(l:info)
    let l:info = split(l:info, "\n")
  endif
  let l:info = maktaba#ensure#IsList(l:info)

  let l:lines = []
  let l:data = {}
  for l:index in range(len(l:info))
    unlet! l:entry l:datum
    let l:entry = l:info[l:index]
    if maktaba#value#IsList(l:entry)
      let [l:line, l:datum] = l:entry
    else
      let l:line = maktaba#ensure#IsString(l:entry)
    endif
    call add(l:lines, l:line)
    if exists('l:datum')
      " Vim line numbers are 1-based.
      let l:data[l:index + 1] = l:datum
    endif
  endfor
  return {
    \ "lines": l:lines,
    \ "data": l:data,
    \ }
endfunction

""
" @private
" Close the window and return to the initial-calling window.
function! maktaba#ui#selector#CloseWindow() abort
  bdelete
  call maktaba#ui#selector#ReturnToWindow()
endfunction


""
" @private
" Return the user to the previous window but don't close the selector window.
function! maktaba#ui#selector#ReturnToWindow() abort
  execute s:last_winnum . 'wincmd w'
  call setpos('.', s:curpos_holder)
  call winrestview(s:current_savedview)
endfunction


""
" @private
" A default function callback that does nothing.
function! maktaba#ui#selector#NoOp(...) abort
endfunction


" Provide the default keymappings.
"
" Key mappings should have the format
" - action: a function to perform when the key is pressed
" - window: how to handle selector window. Generally one of Close, NoOp, or
"   Return
" - description: a string description of what this key does.
function! s:DefaultKeyMappings() abort
  return {
      \ '<CR>': {
      \   'action': function('maktaba#ui#selector#NoOp'),
      \   'window': 'Close',
      \   'description': 'Do something',
      \ }}
endfunction


" Provide the default system keymappings -- i.e., q and h. These are meant to
" be reserved by the selector window.
function! s:SystemDefaultKeyMappings() abort
  return {
      \ 'h': {
      \   'action': function('maktaba#ui#selector#ToggleCurrentHelp'),
      \   'window': 'NoOp',
      \   'description': 'Toggle verbose help messages',
      \ },
      \ 'q': {
      \   'action': function('maktaba#ui#selector#NoOp'),
      \   'window': 'Close',
      \   'description': 'Close the window',
      \ }}
endfunction


" DefaultWindowOptions gets the default window options
" All window options will be set with `setlocal`.
function! s:DefaultWindowOptions() abort
  return [
    \ 'buftype=nofile',
    \ 'bufhidden=delete',
    \ 'noswapfile',
    \ 'readonly',
    \ 'nolist',
    \ 'nomodifiable',
    \ 'nospell',
    \ 'syntax on',
  \ ]
endfunction
