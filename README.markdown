# php-tools

Handy tools for authoring PHP in vim

Defines the `PhpFormatDoc` command.

`PhpFormatDoc` find the nearest function signature (upwards, or downwards if
executed while the cursor is in a function docblock), and update / insert its
associated docblock with proper types and alignments.


## Usage

* Execute `:PhpFormatDoc` while your cursor is within a function or a function
  DocBlock region.

* You might want to wire this to a handy key sequence: `nnoremap <leader>pf <ESC>:PhpFormatDoc<CR>`

* Any existing parameter descriptions will be preserved when the argument name
  matches. Parameter order and types are derived from the function signature.
  When a type is specified in the function signature, it will override any type
  specified in the `@param` line. 

Questions, comments, suggestions, praise and flames should be sent to:

Benjamin Doherty <bendohmv@gmail.com>

