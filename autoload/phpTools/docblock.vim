"
" Tools for creating / updating PHPDocBlock for named functions.
"
" Uses the function signature as the source of truth, preserving any docblock
" types and descriptions. If a function signature omits a type for an argument
" the existing definition is used as the type.
"
" Any return types specified in the function signature will override the return
" types specified in DocBlocks
"
" Attempts to align the types, names and descriptions in @param annotation
" stacks in function docblocks. This is not a perfect solution, but does help
" with an annoying housekeeping requirement to satisfy sniffers.
"
let s:functionPattern = '^\s*\%(abstract\s\+\|final\s\+\|private\s\+\|protected\s\+\|public\s\+\|static\s\+\)*function'
let s:namedFunctionPattern = s:functionPattern . '\_\s*\(\w\+\)'

" Find the bounds of a PHPDocBlock given a line number within that span
function! phpTools#docblock#findDocBlockLines(line)
  call cursor(a:line, '$')

  " find the start line
  let l:startLine = search('/\*\*\n', 'bcW')
  
  " find the endline
  let l:endLine = search('\*/[\s\n ]*[a-z]', 'nW')

  if l:startLine == 0 || l:endLine == 0
    " couldn't find a start or an end
    return []
  endif

  if l:startLine <= a:line && l:endLine >= a:line
    return [l:startLine, l:endLine]
  else
    return []
  endif
endfunction

"
" Parse out function details: name, arguments by type (defaulting to mixed,)
" maybe return type
"
function! phpTools#docblock#parseFunction(funcLine)
  call cursor(a:funcLine, 0)

  let l:functionSignaturePattern = s:namedFunctionPattern . '\_\s*(\(\_.\{-}\))\%(\s*:\s*\(\w\+\)\)\?'

  " parse out arguments from the function which might span multiple line
  let l:matchIndex = search(l:functionSignaturePattern, 'ceW')
  
  if l:matchIndex == 0
    echo 'Unable to match function signature'
    return []
  endif

  let l:functionLines = join(getline(a:funcLine, line('.')))
  let l:matches = matchlist(l:functionLines, l:functionSignaturePattern)

  if empty(l:matches)
    echo "Unable to match function signature in " . l:functionLines
    return []
  endif

  let l:funcName = l:matches[1]
  let l:funcArgs = split(l:matches[2], '\s*,\s*')
  let l:types = {}
  let l:argNames = []

  for l:arg in l:funcArgs
    let l:argTuple = filter(split(l:arg, '\s\+'), 'v:val != ""')

    if len(l:argTuple) == 1 || l:argTuple[1] == '='
      let l:types[l:argTuple[0]] = 'mixed' 
      call add(l:argNames, l:argTuple[0])
    else 
      let l:types[l:argTuple[1]] = l:argTuple[0]
      call add(l:argNames, l:argTuple[1])
    endif
  endfor

  return [l:funcName, l:argNames, l:types, l:matches[3]]
endfunction

" Pull out type hints from the docblock within the lines given
" by lineNums[0]...lineNums[1]
"
" Return [ { name: [ type, description ], return: [ type, description ] }, docTemplate ]
function! phpTools#docblock#parseDocBlockParams(lineNums)
  let l:updatedDoc = ''
  let l:types = {}
  let l:index = 0
  let l:docLines = []
  let l:lastParam = -1 
  let l:lastReturn = -1 

  for l:line in getline(a:lineNums[0], a:lineNums[1])
    let l:matches = matchlist(l:line, '\*\s*@\(param\|return\)\s*\(.*\)')

    if empty(l:matches)
      call add(l:docLines, l:line)
      let l:index += 1
    elseif l:matches[1] == 'param'
      let l:lastParam = l:index

      let l:args = matchlist(l:matches[2], '\(\S*\)\s*\(\S*\)\s*\(.*\)')
      if !empty(l:args)
        let l:types[l:args[2]] = [ l:args[1], l:args[3] ]
      endif
    elseif l:matches[1] == 'return'
      let l:lastReturn = l:index

      let l:args = matchlist(l:matches[2], '\(\S*\)\(.*\)')
      if !empty(l:args)
        let l:types['return'] = [ l:args[1], l:args[2] ]
      endif

    endif
  endfor

  let l:lastLine = matchlist(l:line, '\(\s*\)\*\+/')
  let l:indent = l:lastLine[1]

  let l:paramLine = l:indent . "* @_params\n" . l:indent . "*"
  let l:returnLine = l:indent . '* @_return'

  if l:lastParam == -1 && l:lastReturn > -1
    let l:lastParam = l:lastReturn
  endif
  
  let l:docLines = insert(l:docLines, l:paramLine, l:lastParam)

  " Always put the @_return statement at the end if one doesn't exist
  " or if for some reason it appeared before the parameters
  if l:lastReturn < l:lastParam
    let l:lastReturn = -1
  else
    " compensate for the line inserted for the @_params
    let l:lastReturn += 1
  endif

  let l:docLines = insert(l:docLines, l:returnLine, l:lastReturn)

  let l:outputDoc = join(l:docLines, "\n")
  return [l:types, l:outputDoc]
endfunction

function! phpTools#docblock#docCommentFromArguments()
  " keep track of the original cursor position
  let l:cursorPos = getpos('.')

  " start searching from the end of the current line
  normal $ 

  " find the function backwards that may or may not have a docblock
  let l:functionLine = search(s:namedFunctionPattern, 'ncbW')
  " find the nearest docblock start backwards
  let l:docStartLine = search('/\*\*\n', 'nbcW')

  if l:functionLine == 0 && l:docStartLine == 0
    echo "No function or DocBlock line"
    return
  endif

  " if this was invoked within a docblock, use the next function instead
  if l:docStartLine > l:functionLine
    let l:docLines = phpTools#docblock#findDocBlockLines(l:docStartLine)

    if empty(l:docLines)
      echo "Couldnt find docblock lines"
      return
    endif

    let l:functionLine = l:docLines[1] + 1

    if match(getline(l:functionLine), s:functionPattern) == -1
      echo "Docblock doesnt seem to be attached to a function at " . getline(l:functionLine)
      return
    endif

  elseif l:functionLine > 1
    let l:docLines = phpTools#docblock#findDocBlockLines(l:functionLine - 1)

    " we may not have docblock lines already
    if empty(l:docLines)
      echo "Function No docblock attached to the function"
    endif
  endif

  " Figure out the indent for this function and thus its docs
  let l:indent = repeat(' ', match(getline(l:functionLine), '\S'))

  " we now have the location of the function and its docblock lines
  let l:parsedFunction = phpTools#docblock#parseFunction(l:functionLine)

  if empty(l:parsedFunction)
    echo "Failed to parse types from function!"
  endif

  let l:funcName = l:parsedFunction[0]
  let l:argNames = l:parsedFunction[1]
  let l:sigTypes = l:parsedFunction[2]
  let l:returnType = l:parsedFunction[3]

  if empty(l:docLines)
    let l:docTypes = {}
    let l:newDoc = join([ l:indent . '/**', ' * @_params', ' *', ' * @_return', ' */' ], "\n" . l:indent)
  else
    let l:parsedDocBlock = phpTools#docblock#parseDocBlockParams(l:docLines)
    let l:docTypes = l:parsedDocBlock[0]
    let l:newDoc = l:parsedDocBlock[1]
  endif

  " Build up the ordered set of params, names and descriptions, computing
  " the maximum length of types and names in the process
  let l:params = []
  let l:longestType = 0
  let l:longestName = 0

  for l:name in l:argNames
    let l:type = l:sigTypes[l:name]

    if !empty(get(l:docTypes, l:name))
      let l:docType = l:docTypes[l:name][0]
      let l:docDescription = l:docTypes[l:name][1]

      let l:description = !empty(l:docDescription) ? l:docDescription : '.'
      
      if l:sigTypes[l:name] == 'mixed' && l:docType != 'mixed'
        let l:type = l:docType
      endif
    else
      let l:description = '.'
    endif

    let l:longestType = len(l:type) > l:longestType ? len(l:type) : l:longestType
    let l:longestName = len(l:name) > l:longestName ? len(l:name) : l:longestName

    call add(l:params, [ l:type, l:name, l:description ])
  endfor

  let l:paramLines = []

  for l:param in l:params
    let l:type = l:param[0]
    let l:name = l:param[1]
    let l:description = l:param[2]

    call add(l:paramLines, l:indent . ' * @param ' . l:type . repeat(' ', l:longestType - len(l:type)) . ' ' . l:name . repeat(' ', l:longestName - len(l:name)) . ' ' . l:description)
  endfor

  " Use the docblock @return type only when there's no type in the signature
  if has_key(l:docTypes, 'return') 
    if empty(l:returnType)
      let l:returnType = l:docTypes['return'][0]
    endif

    if !empty(l:docTypes['return'][1])
      let l:returnDescription = l:docTypes['return'][1]
    else
      let l:returnDescription = ''
    endif
  else
    let l:returnDescription = ''
  endif

  if !empty(l:paramLines)
    let l:newDoc = substitute(l:newDoc, '\s*\* @_params\n\s*\*', substitute(join(l:paramLines, "\n"), '\', '\\\\', 'g'), '')
  else
    " No parameters found, just drop the placeholder
    let l:newDoc = substitute(l:newDoc, '\n' . l:indent . ' \* @_params\n' . l:indent . ' \*', '', '')
  endif

  if l:funcName == '__construct'
    " No @return annotation for constructors, drop the placeholder line entirely
    let l:newDoc = substitute(l:newDoc, '\n' . l:indent . ' \* @_return\n' . l:indent . ' \*', '', '')
  else
    let l:newDoc = substitute(l:newDoc, '@_return', substitute('@return ' . l:returnType . l:returnDescription, '\', '\\\\', 'g'), '')
  endif

  call cursor(l:cursorPos[1], l:cursorPos[2])

  if !empty(l:docLines)
    call deletebufline(bufnr('%'), l:docLines[0], l:docLines[1])
    let l:insertOffset = l:docLines[1] - l:docLines[0] + 2
  else
    let l:insertOffset = 1
  endif

  call appendbufline(bufnr('%'), l:functionLine - l:insertOffset, split(l:newDoc, '\n'))
endfunction

