import json
import io

# logger macros?
# OC_ABORT?
# multi pointers for things

# kind: module, typename, union, struct, array, f32, i32, u32, bool, void, char, variadic-param, pointer, namedType
# kind: enum-constant, macro

# exclude oc_* from any string
def prefix_trim_oc(name):
    if name.startswith("_oc_"): # some enums have this
        return name[4:]

    if name.startswith("oc_"):
        return name[3:]

    return name

def get_type_name_or_kind(obj):
    result = obj["kind"] # basic identifiers like f32, int, etc land here
    
    # if it contains an orca name, use that one instead
    if "name" in obj:
        result = prefix_trim_oc(obj["name"]) # names need to be trimmed

    return result

# try using the object kind
# if kind is namedType -> get the namedType name
# if its a pointer do a pointer type or rawptr
def get_inner_kind(obj):
    result = get_type_name_or_kind(obj)
    output = result

    if result == "pointer":
        inner_type = obj["type"]
        result = get_type_name_or_kind(inner_type)

        # convert void to odins rawptr
        if result == "void":
            output = "rawptr"
        else:
            output = "^" + result

        # turn ^char to cstring
        if output == "^char":
            output = "cstring"
    elif result == "namedType":
        inner_type = obj["type"]
        result = get_type_name_or_kind(inner_type)
        output = result

    return output

# generate a single field key & value pair
def gen_param(obj, file):
    name = check_field_name(obj["name"]) # can be ... !
    
    # convert variadic-param to odin #c_vararg args: ..any
    variable_output = get_inner_kind(obj["type"])
    if name == "..." or variable_output == "va_list":
        file.write("#c_vararg args: ..any")
        return

    if name == "context": # context is a keyword in odin
        name = "_context" 

    file.write(f"{name}: {variable_output}")

# generate a multi or single line doc dependant on whats provided
def gen_doc(obj, file, indent):
    indent_str = indent_string(indent)
    if isinstance(obj, list):
        file.write(f"{indent_str}/*\n")
        for line in obj:
            file.write(f"{indent_str}{line}\n")
        file.write(f"{indent_str}*/\n")
    else:
        file.write(f"{indent_str}// {obj}\n")

# if the doc exists write it
def try_gen_doc(obj, file, indent):
    if "doc" in obj:
        gen_doc(obj["doc"], file, indent)

# generate a procedure declation with the parameters and its return type
def gen_proc(obj, name, write_foreign_finish, file, indent):
    kind = obj["kind"]
    name = prefix_trim_oc(name)

    try_gen_doc(obj, file, indent)
    indent_str = indent_string(indent)
    file.write(f"{indent_str}{name} :: proc(")

    # write params
    param_count = 0
    for param in obj["params"]:
        if param_count > 0:
            file.write(", ")

        gen_param(param, file)
        param_count += 1

    file.write(")")

    # write return type when not void
    ret = obj["return"]
    if ret["kind"] != "void":
        ret_kind = get_inner_kind(ret)
        file.write(f" -> {ret_kind}")

    # finish
    if write_foreign_finish:
        file.write(" ---\n")
    else:
        file.write("\n")

# add indentation 
def indent_string(indent):
    return "\t" * indent

# write spacers and actual module docs
def gen_module_doc(obj, file):
    brief = obj["brief"]
    spacer = "//" * 40
    file.write(spacer + "\n")
    file.write(f"// {brief}\n")
    file.write(spacer + "\n" * 2)

# easier builtins instead of struct+unions
type_builtins = {
    "vec2": "[2]f32",
    "vec3": "[3]f32",
    "vec2i": "[2]i32",
    "vec4": "[4]f32",
    "mat2x3": "[2][3]f32", # TODO
    "rect": "[4]f32",
    "color": "[4]f32",

    "ui_layout_align": "[2]ui_align",
    "ui_box_size": "[2]ui_size",
    "ui_box_floating": "[2]bool",
    
    "mat2x3": "#row_major matrix[2, 3]f32",
    
    "utf32": "rune",
    "str8": "string",
    "str16": "distinct []rune",
    "str32": "distinct []u16",
}

# generate a default builtin instead of complex xy or xywh C struct+union pairs
def gen_type_builtins(name, file, indent):
    if name in type_builtins:
        indent_str = indent_string(indent)
        output = type_builtins[name]
        file.write(f"{indent_str}{name} :: {output}\n\n")
        return True

    return False

# get the enum size (u64, i32, etc)
def get_enum_sizing(obj):
    return obj["type"]["kind"]

# since prefixes dont always match the enum name, the table is easier
enum_prefixes_specific = {
    "OC_LOG_LEVEL_",
    "OC_EVENT_",
    "OC_KEY_",
    "OC_SCANCODE_",
    "OC_KEYMOD_",
    "OC_MOUSE_",
    "OC_FILE_DIALOG_",
    "OC_FILE_OPEN_",
    "OC_FILE_ACCESS_",
    "OC_FILE_SEEK_",
    "OC_IO_ERR_",
    "OC_GRADIENT_BLEND_",
    "OC_COLOR_SPACE_",
    "OC_JOINT_",
    "OC_CAP_",
    "OC_INPUT_TEXT_",
    "OC_UI_AXIS_",
    "OC_UI_ALIGN_",
    "OC_UI_SIZE_",
    "OC_UI_STYLE_",
    "OC_UI_SEL_",
    "OC_UI_FLAG_",
    "OC_UI_FLAG_",
    "OC_UI_EDIT_MOVE_",
}

# since the hashset above is unsorted these should be checked last
enum_prefixes_broad = {
    "OC_FILE_",
    "OC_UI_",
    "OC_IO_",
}

# fixup enum names based on prefixes
def simplify_enum_name(name):
    for prefix in enum_prefixes_specific:
        if name.startswith(prefix):
            return name[len(prefix):]

    # check last
    for prefix in enum_prefixes_broad:
        if name.startswith(prefix):
            return name[len(prefix):]

    return name

# safety check since enum field names cant be only numbers
# 0 would be turned to _0
def check_enum_name_decimal(name):
    if name.isdecimal():
        return "_" + name

    return name

# generates an odin enum e.g. log_level :: enum { ... }
def gen_enum(obj, file, name, indent):
    indent_str = indent_string(indent)
    singleton = len(obj["constants"]) <= 1 or name == ""

    # write enum description when not a singleton
    if not singleton:
        enum_sizing = get_enum_sizing(obj)
        file.write(f"{indent_str}{name} :: enum {enum_sizing} {{\n")
        fields_indent_str = indent_string(indent + 1)
    else:
        fields_indent_str = indent_str

    # write enum content from objects
    for const in obj["constants"]:
        real_name = const["name"]
        const_name = simplify_enum_name(real_name)
        const_name = check_enum_name_decimal(const_name)
        
        # Exception for OC_STYLE currently, write out constant names
        if real_name.startswith("OC_UI_STYLE"):
            const_name = real_name[6:]
        
        const_value = const["value"]

        # write docs if they exist
        if "doc" in const:
            const_docs = const["doc"]
            file.write(f"{fields_indent_str}// {const_docs}\n")

        # make it a constant instead of an enum asignment
        assignment = "::" if singleton else "="

        file.write(f"{fields_indent_str}{const_name} {assignment} {const_value}")
        file.write("\n" if singleton else ",\n")

    if singleton:
        file.write("\n")
    else:
        file.write(f"{indent_str}}}\n\n")


# any oddities that need to be checked for field
reserved_field_names = {
    "string", # think this is still allowed but eh
    "matrix",
    "proc",
    "color", # issues when color is also return type...
}

# insert a _ before an identifier that may be invalid
def check_field_name(name):
    for reserved in reserved_field_names:
        if reserved == name:
            return "_" + name

    return name

# generate raw unions fields
def gen_union_fields(obj, file, indent):
    if "fields" not in obj:
        print(f"FIELDS MISSED in union")
        return

    indent_str = indent_string(indent)
    for field in obj["fields"]:
        field_name = check_field_name(field["name"])
        field_kind = get_inner_kind(field["type"])

        # name can be empty
        if field_name == "":
            field_name = "_"

        # generate inner structs within a union
        if field_kind == "struct":
            gen_struct(field["type"], file, field_name, indent)

            # always comma separate
            file.write(",\n")
        elif field_kind == "array":
            gen_fixed_array(field, file, field_name, indent)
        else:
            file.write(f"{indent_str}{field_name}: {field_kind},\n")

# fixed size array in C
def gen_fixed_array(obj, file, field_name, indent):
    indent_str = indent_string(indent)
    variable_type = obj["type"]
    array_size = variable_type["count"]
    array_type = get_inner_kind(variable_type["type"])
    file.write(f"{indent_str}{field_name}: [{array_size}]{array_type},\n")

# write struct fields from objects
def gen_struct_fields(obj, file, indent):
    indent_str = indent_string(indent)
    for field in obj["fields"]:
        field_name = check_field_name(field["name"])
        variable_output = get_inner_kind(field["type"])

        # write docs if they exist
        if "doc" in field:
            field_docs = field["doc"]
            file.write(f"{indent_str}// {field_docs}\n")

        # convert inner unions to raw_unions structs
        if variable_output == "union":
            if field_name == "":
                field_name = "_"

            file.write(f"{indent_str}{field_name}: struct #raw_union {{\n")
            variable_type = field["type"]
            gen_union_fields(variable_type, file, indent + 1)
            file.write(f"{indent_str}}},\n")
        elif variable_output == "array": 
            gen_fixed_array(field, file, field_name, indent)
        else:
            file.write(f"{indent_str}{field_name}: {variable_output},\n")

def gen_structs_manually(file, name):
    if name == "ui_layout":
        file.write("""ui_layout :: struct {
\taxis: ui_axis,
\tusing _: [2]f32,
\tmargin: [2]f32,
\talign: ui_layout_align,
}""")
        return True

    return False

# generate an odin struct with its fields
def gen_struct(obj, file, name, indent):
    indent_str = indent_string(indent)

    # just do this one manually
    if gen_structs_manually(file, name):
        return
    
    # if a struct doesnt have fields just skip fields
    if "fields" not in obj:
        file.write(f"{indent_str}{name} :: struct {{}}")
        return

    # check if its a handle struct only, convert that into a distinct handle
    if len(obj["fields"]) == 1:
        field = obj["fields"][0]
        field_name = check_field_name(field["name"])

        if field_name == "h":
            file.write(f"{indent_str}{name} :: distinct u64")
            return

    seperator = " ::" if indent == 0 else ":"
    file.write(f"{indent_str}{name}{seperator} struct {{\n")
    gen_struct_fields(obj, file, indent + 1)
    file.write(f"{indent_str}}}")

def gen_typedef(obj, file, name, indent):
    indent_str = indent_string(indent)
    typedef_kind = obj["kind"]
    file.write(f"{indent_str}{name} :: {typedef_kind}\n\n")

# main object of the api which could be struct, union, enums or macros (unsupported)
def gen_typename_object(obj, file, indent):
    name = prefix_trim_oc(obj["name"])
    try_gen_doc(obj, file, indent)

    # try looking for a builtin match and leave early if written
    if gen_type_builtins(name, file, indent):
        return

    variable_type = obj["type"]
    kind = variable_type["kind"]

    if kind == "struct":
        gen_struct(variable_type, file, name, indent)
        
        # space out structs
        file.write("\n\n")
    elif kind == "union":
        print(f"union not done {name}")
        file.write(f"{name} :: union {{}}\n\n")
    elif kind == "enum":
        gen_enum(variable_type, file, name, indent)
    elif kind == "proc":
        gen_proc(variable_type, name, False, file, indent)
        file.write("\n")
    else: 
        gen_typedef(variable_type, file, name, indent)

# step through the main module objects
# procedures are written to a temp_block thats written once the module is stepped through
def iterate_object(obj, file, shared_block):
    if obj is None:
        return

    kind = obj["kind"]
    if kind == "module":
        gen_module_doc(obj, file)

    temp_block = io.StringIO("")

    if "contents" in obj:
        for child in obj["contents"]:
            iterate_object(child, file, temp_block)

    # finally write the procedures into the foreign block
    if kind == "module":
        module_size = temp_block.tell()

        # skip empty modules
        if module_size != 0:
            file.write(f"@(default_calling_convention=\"c\", link_prefix=\"oc_\")\nforeign {{\n")
            file.write(temp_block.getvalue())
            file.write("}\n\n")

        temp_block.seek(0)

    temp_block.close()

    if kind == "proc":
        proc_name = obj["name"]
        gen_proc(obj, proc_name, True, shared_block, 1)
    elif kind == "typename":
        gen_typename_object(obj, file, 0)

# write package info and types
def write_package(file):
    file.write("package orca\n\n")
    file.write("import \"core:c\"\n\n")
    file.write("char :: c.char\n")

    # currently missing in the api.json
    file.write("window :: distinct u64\n")

    ## currently missing in the api.json
    file.write("""pool :: struct {
\tarena: arena,
\tfreeList: list,
\tblockSize: u64,
}\n""")

def write_unicode_constants(file):
    file.write("""UNICODE_BASIC_LATIN :: unicode_range { 0x0000, 127 }
UNICODE_C1_CONTROLS_AND_LATIN_1_SUPPLEMENT :: unicode_range { 0x0080, 127 }
UNICODE_LATIN_EXTENDED_A :: unicode_range { 0x0100, 127 }
UNICODE_LATIN_EXTENDED_B :: unicode_range { 0x0180, 207 }
UNICODE_IPA_EXTENSIONS :: unicode_range { 0x0250, 95 }
UNICODE_SPACING_MODIFIER_LETTERS :: unicode_range { 0x02b0, 79 }
UNICODE_COMBINING_DIACRITICAL_MARKS :: unicode_range { 0x0300, 111 }
UNICODE_GREEK_COPTIC :: unicode_range { 0x0370, 143 }
UNICODE_CYRILLIC :: unicode_range { 0x0400, 255 }
UNICODE_CYRILLIC_SUPPLEMENT :: unicode_range { 0x0500, 47 }
UNICODE_ARMENIAN :: unicode_range { 0x0530, 95 }
UNICODE_HEBREW :: unicode_range { 0x0590, 111 }
UNICODE_ARABIC :: unicode_range { 0x0600, 255 }
UNICODE_SYRIAC :: unicode_range { 0x0700, 79 }
UNICODE_THAANA :: unicode_range { 0x0780, 63 }
UNICODE_DEVANAGARI :: unicode_range { 0x0900, 127 }
UNICODE_BENGALI_ASSAMESE :: unicode_range { 0x0980, 127 }
UNICODE_GURMUKHI :: unicode_range { 0x0a00, 127 }
UNICODE_GUJARATI :: unicode_range { 0x0a80, 127 }
UNICODE_ORIYA :: unicode_range { 0x0b00, 127 }
UNICODE_TAMIL :: unicode_range { 0x0b80, 127 }
UNICODE_TELUGU :: unicode_range { 0x0c00, 127 }
UNICODE_KANNADA :: unicode_range { 0x0c80, 127 }
UNICODE_MALAYALAM :: unicode_range { 0x0d00, 255 }
UNICODE_SINHALA :: unicode_range { 0x0d80, 127 }
UNICODE_THAI :: unicode_range { 0x0e00, 127 }
UNICODE_LAO :: unicode_range { 0x0e80, 127 }
UNICODE_TIBETAN :: unicode_range { 0x0f00, 255 }
UNICODE_MYANMAR :: unicode_range { 0x1000, 159 }
UNICODE_GEORGIAN :: unicode_range { 0x10a0, 95 }
UNICODE_HANGUL_JAMO :: unicode_range { 0x1100, 255 }
UNICODE_ETHIOPIC :: unicode_range { 0x1200, 383 }
UNICODE_CHEROKEE :: unicode_range { 0x13a0, 95 }
UNICODE_UNIFIED_CANADIAN_ABORIGINAL_SYLLABICS :: unicode_range { 0x1400, 639 }
UNICODE_OGHAM :: unicode_range { 0x1680, 31 }
UNICODE_RUNIC :: unicode_range { 0x16a0, 95 }
UNICODE_TAGALOG :: unicode_range { 0x1700, 31 }
UNICODE_HANUNOO :: unicode_range { 0x1720, 31 }
UNICODE_BUHID :: unicode_range { 0x1740, 31 }
UNICODE_TAGBANWA :: unicode_range { 0x1760, 31 }
UNICODE_KHMER :: unicode_range { 0x1780, 127 }
UNICODE_MONGOLIAN :: unicode_range { 0x1800, 175 }
UNICODE_LIMBU :: unicode_range { 0x1900, 79 }
UNICODE_TAI_LE :: unicode_range { 0x1950, 47 }
UNICODE_KHMER_SYMBOLS :: unicode_range { 0x19e0, 31 }
UNICODE_PHONETIC_EXTENSIONS :: unicode_range { 0x1d00, 127 }
UNICODE_LATIN_EXTENDED_ADDITIONAL :: unicode_range { 0x1e00, 255 }
UNICODE_GREEK_EXTENDED :: unicode_range { 0x1f00, 255 }
UNICODE_GENERAL_PUNCTUATION :: unicode_range { 0x2000, 111 }
UNICODE_SUPERSCRIPTS_AND_SUBSCRIPTS :: unicode_range { 0x2070, 47 }
UNICODE_CURRENCY_SYMBOLS :: unicode_range { 0x20a0, 47 }
UNICODE_COMBINING_DIACRITICAL_MARKS_FOR_SYMBOLS :: unicode_range { 0x20d0, 47 }
UNICODE_LETTERLIKE_SYMBOLS :: unicode_range { 0x2100, 79 }
UNICODE_NUMBER_FORMS :: unicode_range { 0x2150, 63 }
UNICODE_ARROWS :: unicode_range { 0x2190, 111 }
UNICODE_MATHEMATICAL_OPERATORS :: unicode_range { 0x2200, 255 }
UNICODE_MISCELLANEOUS_TECHNICAL :: unicode_range { 0x2300, 255 }
UNICODE_CONTROL_PICTURES :: unicode_range { 0x2400, 63 }
UNICODE_OPTICAL_CHARACTER_RECOGNITION :: unicode_range { 0x2440, 31 }
UNICODE_ENCLOSED_ALPHANUMERICS :: unicode_range { 0x2460, 159 }
UNICODE_BOX_DRAWING :: unicode_range { 0x2500, 127 }
UNICODE_BLOCK_ELEMENTS :: unicode_range { 0x2580, 31 }
UNICODE_GEOMETRIC_SHAPES :: unicode_range { 0x25a0, 95 }
UNICODE_MISCELLANEOUS_SYMBOLS :: unicode_range { 0x2600, 255 }
UNICODE_DINGBATS :: unicode_range { 0x2700, 191 }
UNICODE_MISCELLANEOUS_MATHEMATICAL_SYMBOLS_A :: unicode_range { 0x27c0, 47 }
UNICODE_SUPPLEMENTAL_ARROWS_A :: unicode_range { 0x27f0, 15 }
UNICODE_BRAILLE_PATTERNS :: unicode_range { 0x2800, 255 }
UNICODE_SUPPLEMENTAL_ARROWS_B :: unicode_range { 0x2900, 127 }
UNICODE_MISCELLANEOUS_MATHEMATICAL_SYMBOLS_B :: unicode_range { 0x2980, 127 }
UNICODE_SUPPLEMENTAL_MATHEMATICAL_OPERATORS :: unicode_range { 0x2a00, 255 }
UNICODE_MISCELLANEOUS_SYMBOLS_AND_ARROWS :: unicode_range { 0x2b00, 255 }
UNICODE_CJK_RADICALS_SUPPLEMENT :: unicode_range { 0x2e80, 127 }
UNICODE_KANGXI_RADICALS :: unicode_range { 0x2f00, 223 }
UNICODE_IDEOGRAPHIC_DESCRIPTION_CHARACTERS :: unicode_range { 0x2ff0, 15 }
UNICODE_CJK_SYMBOLS_AND_PUNCTUATION :: unicode_range { 0x3000, 63 }
UNICODE_HIRAGANA :: unicode_range { 0x3040, 95 }
UNICODE_KATAKANA :: unicode_range { 0x30a0, 95 }
UNICODE_BOPOMOFO :: unicode_range { 0x3100, 47 }
UNICODE_HANGUL_COMPATIBILITY_JAMO :: unicode_range { 0x3130, 95 }
UNICODE_KANBUN_KUNTEN :: unicode_range { 0x3190, 15 }
UNICODE_BOPOMOFO_EXTENDED :: unicode_range { 0x31a0, 31 }
UNICODE_KATAKANA_PHONETIC_EXTENSIONS :: unicode_range { 0x31f0, 15 }
UNICODE_ENCLOSED_CJK_LETTERS_AND_MONTHS :: unicode_range { 0x3200, 255 }
UNICODE_CJK_COMPATIBILITY :: unicode_range { 0x3300, 255 }
UNICODE_CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A :: unicode_range { 0x3400, 6591 }
UNICODE_YIJING_HEXAGRAM_SYMBOLS :: unicode_range { 0x4dc0, 63 }
UNICODE_CJK_UNIFIED_IDEOGRAPHS :: unicode_range { 0x4e00, 20911 }
UNICODE_YI_SYLLABLES :: unicode_range { 0xa000, 1167 }
UNICODE_YI_RADICALS :: unicode_range { 0xa490, 63 }
UNICODE_HANGUL_SYLLABLES :: unicode_range { 0xac00, 11183 }
UNICODE_HIGH_SURROGATE_AREA :: unicode_range { 0xd800, 1023 }
UNICODE_LOW_SURROGATE_AREA :: unicode_range { 0xdc00, 1023 }
UNICODE_PRIVATE_USE_AREA :: unicode_range { 0xe000, 6399 }
UNICODE_CJK_COMPATIBILITY_IDEOGRAPHS :: unicode_range { 0xf900, 511 }
UNICODE_ALPHABETIC_PRESENTATION_FORMS :: unicode_range { 0xfb00, 79 }
UNICODE_ARABIC_PRESENTATION_FORMS_A :: unicode_range { 0xfb50, 687 }
UNICODE_VARIATION_SELECTORS :: unicode_range { 0xfe00, 15 }
UNICODE_COMBINING_HALF_MARKS :: unicode_range { 0xfe20, 15 }
UNICODE_CJK_COMPATIBILITY_FORMS :: unicode_range { 0xfe30, 31 }
UNICODE_SMALL_FORM_VARIANTS :: unicode_range { 0xfe50, 31 }
UNICODE_ARABIC_PRESENTATION_FORMS_B :: unicode_range { 0xfe70, 143 }
UNICODE_HALFWIDTH_AND_FULLWIDTH_FORMS :: unicode_range { 0xff00, 239 }
UNICODE_SPECIALS :: unicode_range { 0xfff0, 15 }
UNICODE_LINEAR_B_SYLLABARY :: unicode_range { 0x10000, 127 }
UNICODE_LINEAR_B_IDEOGRAMS :: unicode_range { 0x10080, 127 }
UNICODE_AEGEAN_NUMBERS :: unicode_range { 0x10100, 63 }
UNICODE_OLD_ITALIC :: unicode_range { 0x10300, 47 }
UNICODE_GOTHIC :: unicode_range { 0x10330, 31 }
UNICODE_UGARITIC :: unicode_range { 0x10380, 31 }
UNICODE_DESERET :: unicode_range { 0x10400, 79 }
UNICODE_SHAVIAN :: unicode_range { 0x10450, 47 }
UNICODE_OSMANYA :: unicode_range { 0x10480, 47 }
UNICODE_CYPRIOT_SYLLABARY :: unicode_range { 0x10800, 63 }
UNICODE_BYZANTINE_MUSICAL_SYMBOLS :: unicode_range { 0x1d000, 255 }
UNICODE_MUSICAL_SYMBOLS :: unicode_range { 0x1d100, 255 }
UNICODE_TAI_XUAN_JING_SYMBOLS :: unicode_range { 0x1d300, 95 }
UNICODE_MATHEMATICAL_ALPHANUMERIC_SYMBOLS :: unicode_range { 0x1d400, 1023 }
UNICODE_CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B :: unicode_range { 0x20000, 42719 }
UNICODE_CJK_COMPATIBILITY_IDEOGRAPHS_SUPPLEMENT :: unicode_range { 0x2f800, 543 }
UNICODE_TAGS :: unicode_range { 0xe0000, 127 }
UNICODE_VARIATION_SELECTORS_SUPPLEMENT :: unicode_range { 0xe0100, 239 }
UNICODE_SUPPLEMENTARY_PRIVATE_USE_AREA_A :: unicode_range { 0xf0000, 65533 }
UNICODE_SUPPLEMENTARY_PRIVATE_USE_AREA_B  :: unicode_range { 0x100000, 65533 }
""")

def write_clock(file):
    file.write("""clock_kind :: enum c.int {
\tMONOTONIC,
\tUPTIME,
\tDATE,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
\tclock_time :: proc(clock: clock_kind) -> f64 ---
}
""")

if __name__ == "__main__":
    with open("api.json", "r") as api_file:
        api_desc = json.load(api_file)

    with open("orca.odin", "w") as odin_file:
        write_package(odin_file)
        write_unicode_constants(odin_file)
        write_clock(odin_file)
        temp_block = io.StringIO("")
        
        for module in api_desc:
            iterate_object(module, odin_file, temp_block)
        
        temp_block.close()