declare-option -hidden str peneira_path %sh{ dirname $kak_source }
declare-option -hidden int peneira_selected_line 1
declare-option -hidden range-specs peneira_matches
declare-option -hidden str peneira_previous_prompt
declare-option -hidden str peneira_temp_file

set-face global PeneiraSelected default,rgba:44444422
set-face global PeneiraMatches value

define-command peneira-filter -params 3 -docstring %{
    peneira-filter <prompt> <candidates> <cmd>: filter <candidates> and then run <cmd> with its first argument set to the selected candidate.
} %{
    edit -scratch *peneira*
    peneira-configure-buffer

    set-option buffer peneira_temp_file %sh{
        file=$(mktemp)
        # Execute command that generates candidates and populate temp file
        $2 > $file
        # Write temp file name to peneira_temp_file option
        printf "%s" $file
    }

    # Populate *peneira* buffer with the contents of the temp file
    execute-keys "%%| cat %opt{peneira_temp_file}<ret>gg"

    prompt -on-change %{
        evaluate-commands -buffer *peneira* -save-regs dquote %{
            peneira-filter-buffer "%val{text}"
            # After filtering *peneira* buffer's contents, update temp file
            write %opt{peneira_temp_file}
        }

        # Save current prompt contents to be compared against the prompt of the
        # next iteration
        set-option buffer peneira_previous_prompt "%val{text}"
        execute-keys "<a-;>%opt{peneira_selected_line}g"

    } -on-abort %{
        nop %sh{ rm $kak_opt_peneira_temp_file }
        delete-buffer *peneira*

    } %arg{1} %{
        evaluate-commands -save-regs ac %{
            # Copy selected line to register a
            execute-keys -buffer *peneira* %opt{peneira_selected_line}gx_\"ay
            # Copy <cmd> to register c
            set-register c "%arg{3}"
            peneira-call "%reg{a}"
        }

        evaluate-commands -buffer *peneira* %{
            nop %sh{ rm $kak_opt_peneira_temp_file }
        }

        delete-buffer *peneira*
    }
}

define-command -hidden peneira-configure-buffer %{
	remove-highlighter window/number-lines
	add-highlighter window/current-line line %opt{peneira_selected_line} PeneiraSelected
    add-highlighter window/peneira-matches ranges peneira_matches
	face window PrimaryCursor @PeneiraSelected
	map buffer prompt <down> "<a-;>: peneira-select-next-line<ret>"
	map buffer prompt <tab> "<a-;>: peneira-select-next-line<ret>"
	map buffer prompt <up> "<a-;>: peneira-select-previous-line<ret>"
	map buffer prompt <s-tab> "<a-;>: peneira-select-previous-line<ret>"
}

define-command -hidden peneira-select-previous-line %{
    lua %opt{peneira_selected_line} %val{buf_line_count} %{
        local selected, line_count = args()
        selected = selected > 1 and selected - 1 or line_count
        kak.set_option("buffer", "peneira_selected_line", selected)
    	kak.add_highlighter("-override", "window/current-line", "line", selected, "PeneiraSelected")
    }
}

define-command -hidden peneira-select-next-line %{
    lua %opt{peneira_selected_line} %val{buf_line_count} %{
        local selected, line_count = args()
        selected = selected % line_count + 1
        kak.set_option("buffer", "peneira_selected_line", selected)
    	kak.add_highlighter("-override", "window/current-line", "line", selected, "PeneiraSelected")
    }
}

# arg: prompt text
define-command -hidden peneira-filter-buffer -params 1 %{
    lua %opt{peneira_previous_prompt} %arg{1} %{
        local previous_prompt, prompt = args()

        if #prompt < #previous_prompt then
            kak.execute_keys("u")
            return
        end

        kak.peneira_refine_filter(prompt)
    }
}

# arg: prompt text
define-command -hidden peneira-refine-filter -params 1 %{
    lua %opt{peneira_path} %opt{peneira_temp_file} %arg{1} %{
        local peneira_path, filename, prompt = args()

        if #prompt == 0 then
            return
        end

        -- Add plugin path to the list of path to be searched by `require`
        package.path = string.format("%s/?.lua;%s", peneira_path, package.path)
        local peneira = require "peneira"

        local lines, positions = peneira.filter(filename, prompt)
        if not lines then return end

        kak.set_register("dquote", table.concat(lines, "\n"))
		kak.execute_keys("%R")

        local range_specs = peneira.range_specs(positions)
		kak.peneira_highlight_matches(table.concat(range_specs, "\n"))
	}
}

# arg: range specs
define-command -hidden peneira-highlight-matches -params 1 %{
	lua %val{timestamp} %arg{1} %{
        local timestamp, range_specs_text = args()
        local range_specs = {}

        for spec in range_specs_text:gmatch("[^\n]+") do
            range_specs[#range_specs + 1] = spec
        end

        kak.set_option("buffer", "peneira_matches", timestamp, unpack(range_specs))
	}
}

# Calls the command stored in the c register. This way, that command can use the
# argument passed to peneira-call as if it was an argument passed to it.
define-command -hidden peneira-call -params 1 %{
    evaluate-commands "%reg{c}"
}

define-command peneira-files -docstring %{
    peneira-files: select a file in the current directory tree
} %{
    peneira-filter 'files: ' %{ fd } %{
        edit %arg{1}
    }
}
