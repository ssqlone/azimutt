import {anyAsString, distinct, isNotUndefined} from "@azimutt/utils";
import {
    Attribute,
    attributeExtraKeys,
    attributePathFromId,
    attributesRefFromId,
    Database,
    Entity,
    entityExtraKeys,
    entityRefFromId,
    entityRefSame,
    entityRefToId,
    entityToRef,
    Extra,
    flattenAttributes,
    getAttribute,
    ParserError,
    Relation,
    RelationAction,
    relationExtraKeys,
    Type,
    typeToId
} from "@azimutt/models";
import {parseAml} from "../index";
import {genAttributeRef} from "../amlGenerator";
import {
    CancellationToken,
    CodeAction,
    CodeActionContext,
    CodeActionList,
    CodeActionProvider,
    CodeActionTriggerType,
    CodeLens,
    CodeLensList,
    CodeLensProvider,
    CompletionContext,
    CompletionItem,
    CompletionItemInsertTextRule,
    CompletionItemKind,
    CompletionItemProvider,
    CompletionList,
    IMarkerData,
    IMonarchLanguage,
    IStandaloneCodeEditor,
    ITextModel,
    MarkerSeverity,
    Position,
    ProviderResult,
    Range
} from "./monaco.types";

// TODO: use hover provider to show entity/type definition or AML doc
// TODO: enable refactorings to rename an entity/attribute (ctrl+r)

// keep Regex in sync with backend/assets/js/aml.hljs.ts
export const entityRegex = /^[a-zA-Z_][a-zA-Z0-9_#]*/
export const attributeNameRegex = /^ +[a-zA-Z_][a-zA-Z0-9_#]*/
export const attributeTypeRegex = /\b(uuid|(var|n)?char2?|character( varying)?|(tiny|medium|long|ci)?text|(tiny|small|big)?int(eger)?(\d+)?|numeric|float|double( precision)?|bool(ean)?|timestamp( with(out)? time zone)?|date(time)?|time( with(out)? time zone)?|interval|json|string|number)\b/
export const keywordRegex = /\b(namespace|nullable|pk|index|unique|check|fk|rel|type)\b/
export const notesRegex = /\|[^#\n]*/
export const commentRegex = /#.*/

// other lang inspiration: https://github.com/microsoft/monaco-editor/tree/main/src

// see https://microsoft.github.io/monaco-editor/monarch.html
// see https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-custom-languages
export const language = (opts: {} = {}): IMonarchLanguage => ({ // syntax highlighting
    ignoreCase: true,
    // defaultToken: 'invalid', // comment this when not working on language
    tokenizer: {
        root: [
            [entityRegex, 'entity'],
            [attributeNameRegex, 'attribute'],
            [attributeTypeRegex, 'type'],
            [keywordRegex, 'keyword'],
            [/(->|fk) [^ ]+/, 'operators'],
            [notesRegex, 'comment.doc'],
            [commentRegex, 'comment'],
        ],
    }
})

// see https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-custom-languages
// export const theme = (opts: {} = {}): ({})

// see https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-completion-provider-example
export const completion = (opts: {} = {}): CompletionItemProvider => ({ // auto-complete
    triggerCharacters: [' ', '(', '{', ',', '.'],
    provideCompletionItems(model: ITextModel, position: Position, context: CompletionContext, token: CancellationToken): ProviderResult<CompletionList> {
        // const autoCompletion = !!context.triggerCharacter // if completion is automatically triggered or manually (cf triggerCharacters)
        const suggestions: CompletionItem[] = []
        const before = model.getLineContent(position.lineNumber).slice(0, position.column - 1) // the text before the cursor
        // const after = model.getLineContent(position.lineNumber).slice(position.column - 1) // the text after the cursor
        // console.log(`provideCompletionItems(<${before}> | <${after}>)`)
        const prevLine = position.lineNumber > 1 ? model.getLineContent(position.lineNumber - 1) : ''
        let database: Database | undefined = (model as any).context?.database // parsed database can be set externally (avoid parsing twice), use let for lazy parsing only if needed
        const getDb = (): Database => {
            // lazily parse the model if needed
            database = database || parseAml(model.getValue()).result
            return database || {}
        }
        const getEntities = (): Entity[] => getDb().entities || []
        const getAttributes = (): Attribute[] => getEntities().flatMap(e => flattenAttributes(e.attrs))
        const getRelations = (): Relation[] => getDb().relations || []
        const getTypes = (): Type[] => getDb().types || []
        let res: string[] | undefined // storing match result
        if (res = entityWrittenMatch(before)) {
            const [name] = res
            if (name === 'rel') {
                getEntities().map(e => entityRefToId(entityToRef(e)))
                    .filter(e => e !== 're') // it's generated by typing the `rel` keyword ^^
                    .forEach(e => suggestions.push(suggestText(e, CompletionItemKind.User, position)))
            } else if (name === 'type') {
                // nothing yet
            } else {
                suggestExtra(suggestions, position, '')
            }
        }
        if (attributeIndentationMatch(before)) {
            if (prevLine.match(/^[a-zA-Z_][a-zA-Z0-9_#]*/)) { // on first attribute
                suggestions.push(suggestText('  id uuid pk'.replace(before, ''), CompletionItemKind.User, position))
                suggestions.push(suggestText('  id bigint pk {autoIncrement}'.replace(before, ''), CompletionItemKind.User, position))
            }
        }
        if (res = attributeNameWrittenMatch(before)) {
            const [attributeName] = res
            if (attributeName === 'id' && !!prevLine.match(/^[a-zA-Z_][a-zA-Z0-9_#]*/)) { // on first attribute
                suggestions.push(suggestText('uuid pk', CompletionItemKind.User, position))
                suggestions.push(suggestText('bigint pk {autoIncrement}', CompletionItemKind.User, position))
            }
            if (attributeName.endsWith('_id') || attributeName.endsWith('Id')) {
                suggestRelationRef(suggestions, position, getEntities(), 1, '-> ')
            }
            if (attributeName.endsWith('_at') || attributeName.endsWith('At')) {
                suggestions.push(suggestText('timestamp=`now()`', CompletionItemKind.TypeParameter, position))
            }
            suggestAttributeType(getTypes(), getAttributes(), suggestions, position)
        }
        if (attributeTypeWrittenMatch(before)) { // wrote attribute type
            const [, indent] = before.match(/^( +)/) || []
            suggestAttributeProps(suggestions, position)
            suggestExtra(suggestions, position, indent)
        }
        if (res = attributeRootMatch(before)) {
            const [refId] = res
            const attrs = getEntities().find(e => entityRefSame(entityToRef(e), entityRefFromId(refId)))?.attrs || []
            attrs.forEach(attr => suggestions.push(suggestText(attr.name, CompletionItemKind.Class, position)))
        }
        if (res = attributeNestedMatch(before)) {
            const [refId, pathId] = res
            const attrs = getEntities().find(e => entityRefSame(entityToRef(e), entityRefFromId(refId)))?.attrs
            const children = getAttribute(attrs, attributePathFromId(pathId))?.attrs || []
            children.forEach(attr => suggestions.push(suggestText(attr.name, CompletionItemKind.Class, position)))
        }
        if (relationLinkWrittenMatch(before)) {
            suggestRelationRef(suggestions, position, getEntities(), undefined, '')
        }
        if (res = relationSrcWrittenMatch(before)) {
            const [srcId] = res
            // TODO: sort target attributes in the same order then src if possible
            suggestRelationRef(suggestions, position, getEntities(), attributesRefFromId(srcId).attrs.length, '-> ')
        }
        if (res = entityPropsKeyMatch(before)) {
            if (!res.includes('view')) suggestions.push(suggestSnippet('view', 'view: "${1:query}"', CompletionItemKind.Property, position))
            if (!res.includes('color')) suggestions.push(suggestText('color', CompletionItemKind.Property, position, {insert: 'color:'}))
            if (!res.includes('tags')) suggestions.push(suggestSnippet('tags', 'tags: [${1:tag}]', CompletionItemKind.Property, position))
            suggestPropKeys(getEntities(), entityExtraKeys, suggestions, position)
        }
        if (res = entityPropsValueMatch(before)) {
            const [prop] = res
            if (prop === 'color') 'red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose gray'.split(' ').forEach(color => suggestions.push(suggestText(color, CompletionItemKind.Value, position)))
            if (prop === 'tags') suggestTagValues(getEntities().flatMap(e => e.extra?.tags || []), suggestions, position)
            if (!entityExtraKeys.includes(prop)) suggestPropValues(getEntities().map(e => e.extra?.[prop]), suggestions, position)
        }
        if (res = attributePropsKeyMatch(before)) {
            if (!res.includes('autoIncrement')) suggestions.push(suggestText('autoIncrement', CompletionItemKind.Property, position))
            if (!res.includes('hidden')) suggestions.push(suggestText('hidden', CompletionItemKind.Property, position))
            if (!res.includes('tags')) suggestions.push(suggestSnippet('tags', 'tags: [${1:tag}]', CompletionItemKind.Property, position))
            suggestPropKeys(getAttributes(), attributeExtraKeys, suggestions, position)
        }
        if (res = attributePropsValueMatch(before)) {
            const [prop] = res
            if (prop === 'tags') suggestTagValues(getAttributes().flatMap(a => a.extra?.tags || []), suggestions, position)
            if (!attributeExtraKeys.includes(prop)) suggestPropValues(getAttributes().map(a => a.extra?.[prop]), suggestions, position)
        }
        if (res = relationPropsKeyMatch(before)) {
            if (!res.includes('onUpdate')) suggestions.push(suggestText('onUpdate', CompletionItemKind.Property, position, {insert: 'onUpdate:'}))
            if (!res.includes('onDelete')) suggestions.push(suggestText('onDelete', CompletionItemKind.Property, position, {insert: 'onDelete:'}))
            if (!res.includes('tags')) suggestions.push(suggestSnippet('tags', 'tags: [${1:tag}]', CompletionItemKind.Property, position))
            suggestPropKeys(getRelations(), relationExtraKeys, suggestions, position)
        }
        if (res = relationPropsValueMatch(before)) {
            const [prop] = res
            if (prop === 'onUpdate' || prop === 'onDelete') Object.keys(RelationAction.enum).forEach(action => suggestions.push(suggestText(action.includes(' ') ? '"' + action + '"' : action, CompletionItemKind.Value, position)))
            if (prop === 'tags') suggestTagValues(getRelations().flatMap(r => r.extra?.tags || []), suggestions, position)
            if (!relationExtraKeys.includes(prop)) suggestPropValues(getAttributes().map(r => r.extra?.[prop]), suggestions, position)
        }
        // TODO: suggest attribute missing options even when some are already set
        // TODO: relation written => extra
        // TODO: type written => extra
        return {suggestions}
    },
    /*resolveCompletionItem(item: CompletionItem, token: CancellationToken): ProviderResult<CompletionItem> {
        console.log('resolveCompletionItem', item)
        return undefined
    }*/
})

const completionMatch = (line: string, regex: RegExp): string[] | undefined => {
    const res = line.match(regex)
    return res ? [...res.slice(1)] : undefined
}
const entityNameR = '[a-zA-Z_][a-zA-Z0-9_#]*' // miss quoted name
const entityRefR = '[a-zA-Z_][a-zA-Z0-9_#.]*' // too simplistic (just allowing '.' to capture all segments)
const attributeNameR = '[a-zA-Z_][a-zA-Z0-9_#]*' // miss quoted name
const attributeTypeR = '[a-zA-Z_][a-zA-Z0-9_#]*'
const attributePathR = '[a-zA-Z_][a-zA-Z0-9_#.]*' // too simplistic (just allowing '.' to capture all segments)
const attributeValueR = '[a-zA-Z0-9_]+'
const attributePathsR = ' *[a-zA-Z_][a-zA-Z0-9_#., ]*' // too simplistic (just allowing '.', ' ' and ',' to capture everything)
const relationCardinalityR = '[-<>]'
const propKeyR = '[a-zA-Z0-9]+'
const propValueR = '[^,]+'
const relationPolyR = `${attributeNameR}=${attributeValueR}`
const startsWithKeyword = (line: string): boolean => line.startsWith('namespace ') || line.startsWith('rel ') || line.startsWith('fr ') || line.startsWith('type ')
export const entityWrittenMatch = (line: string): string[] | undefined => startsWithKeyword(line) ? undefined : completionMatch(line, new RegExp(`^(${entityNameR}) +$`))
export const attributeIndentationMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^( +)$`))
export const attributeNameWrittenMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^ +(${attributeNameR}) +$`))
export const attributeTypeWrittenMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^ +(${attributeNameR}) +(${attributeTypeR}) +$`))
export const attributeRootMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`(${entityRefR})\\((?: *${attributePathR} *,)* *$`))
export const attributeNestedMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`(${entityRefR})\\((?: *${attributePathR} *,)* *(${attributePathR})\\.$`))
export const relationLinkWrittenMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`(${relationCardinalityR})(${relationPolyR})?(${relationCardinalityR}) +$`))
export const relationSrcWrittenMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^rel +(${entityRefR}\\(${attributePathsR}\\)) +$`))
export const entityPropsKeyMatch = (line: string): string[] | undefined => startsWithKeyword(line) ? undefined : completionMatch(line, new RegExp(`^${entityNameR} +.*{((?: *${propKeyR} *(?:: *${propValueR} *)?,)*) *$`))?.flatMap(m => m.split(',')).map(p => p.split(':')[0].trim()).filter(k => !!k)
export const entityPropsValueMatch = (line: string): string[] | undefined => startsWithKeyword(line) ? undefined : completionMatch(line, new RegExp(`^${entityNameR} +.*{(?: *${propKeyR} *(?:: *${propValueR} *)?,)* *(${propKeyR}) *: *[["]?$`))
export const attributePropsKeyMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^ +${attributeNameR} +.*{((?: *${propKeyR} *(?:: *${propValueR} *)?,)*) *$`))?.flatMap(m => m.split(',')).map(p => p.split(':')[0].trim()).filter(k => !!k)
export const attributePropsValueMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^ +${attributeNameR} +.*{(?: *${propKeyR} *(?:: *${propValueR} *)?,)* *(${propKeyR}) *: *[["]?$`))
export const relationPropsKeyMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^rel +.*{((?: *${propKeyR} *(?:: *${propValueR} *)?,)*) *$`))?.flatMap(m => m.split(',')).map(p => p.split(':')[0].trim()).filter(k => !!k)
export const relationPropsValueMatch = (line: string): string[] | undefined => completionMatch(line, new RegExp(`^rel +.*{(?: *${propKeyR} *(?:: *${propValueR} *)?,)* *(${propKeyR}) *: *[["]?$`))

export function suggestAttributeType(types: Type[], attributes: Attribute[], suggestions: CompletionItem[], position: Position): void {
    const toSuggest = ['varchar', 'text', 'integer', 'bigint', 'boolean', 'uuid', 'timestamp', '"timestamp with time zone"', 'json', 'jsonb', 'string', 'number'].concat(types.map(typeToId), attributes.map(a => a.type))
    distinct(toSuggest).forEach(type => suggestions.push(suggestText(type, CompletionItemKind.TypeParameter, position)))
}
export function suggestAttributeProps(suggestions: CompletionItem[], position: Position): void {
    suggestions.push(suggestText('pk', CompletionItemKind.User, position))
    suggestions.push(suggestText('unique', CompletionItemKind.Issue, position))
    suggestions.push(suggestText('index', CompletionItemKind.Property, position))
    suggestions.push(suggestSnippet('check', 'check(`${1:predicate}`)', CompletionItemKind.Operator, position))
    suggestions.push(suggestText('->', CompletionItemKind.Interface, position))
}
export function suggestRelationRef(suggestions: CompletionItem[], position: Position, entities: Entity[], attrs: number | undefined, prefix: string): void {
    entities.map(e => e.pk && (attrs === undefined || e.pk.attrs.length === attrs) ? prefix + genAttributeRef({...entityToRef(e), attrs: e.pk.attrs}, {}, false, undefined, false) : '')
        .filter(rel => !!rel)
        .forEach(rel => suggestions.push(suggestText(rel, CompletionItemKind.Interface, position)))
}
export function suggestExtra(suggestions: CompletionItem[], position: Position, indent: string): void {
    suggestions.push(suggestSnippet('{key: value}', '{${1:key}: ${2:value}}', CompletionItemKind.File, position, {documentation: 'add properties'}))
    suggestions.push(suggestSnippet('| inline doc', '| ${1:your doc}', CompletionItemKind.File, position, {documentation: 'add documentation'}))
    suggestions.push(suggestSnippet('||| multi-line doc', `|||\n${indent}  \${1:your doc}\n${indent}|||`, CompletionItemKind.File, position, {documentation: 'add documentation'}))
    suggestions.push(suggestSnippet('# comment', '# ${1:your comment}', CompletionItemKind.File, position, {documentation: 'add comment'}))
}
function suggestTagValues(tags: string[], suggestions: CompletionItem[], position: Position): void {
    distinct(tags).filter(tag => typeof tag === 'string').forEach(tag => suggestions.push(suggestText(tag, CompletionItemKind.Value, position)))
}
function suggestPropKeys(items: {extra?: Extra}[], ignore: string[], suggestions: CompletionItem[], position: Position): void {
    const props: string[] = items.flatMap(i => Object.keys(i.extra || {}).filter(k => !ignore.includes(k)))
    distinct(props).forEach(prop => suggestions.push(suggestText(prop, CompletionItemKind.Property, position, {insert: `${prop}:`})))
}
function suggestPropValues(values: unknown[], suggestions: CompletionItem[], position: Position): void {
    const vals = values.flatMap(v => Array.isArray(v) ? v : [v]).map(anyAsString).filter(v => !!v)
    distinct(vals).forEach(v => suggestions.push(suggestText(v, CompletionItemKind.Value, position)))
}

export const codeAction = (opts: {} = {}): CodeActionProvider => ({ // quick-fixes
    provideCodeActions(model: ITextModel, range: Range, context: CodeActionContext, token: CancellationToken): ProviderResult<CodeActionList> {
        if (context.trigger === CodeActionTriggerType.Invoke && context.only === 'quickfix') { // hover a marker
            const actions: CodeAction[] = context.markers.map(m => {
                const [, prev, next] = m.message.match(/"([^"]{1,100})".{1,100}legacy.{1,100}"([^"]{1,100})"/) || []
                if (next) {
                    return {
                        title: `Replace by '${next}'`,
                        diagnostics: [m],
                        kind: 'quickfix',
                        edit: {edits: [{
                            resource: model.uri,
                            versionId: model.getVersionId(),
                            textEdit: {text: next, range}
                        }]}
                    }
                }
            }).filter(isNotUndefined)
            return {actions, dispose() {}}
        }
        /*if (context.trigger === CodeActionTriggerType.Auto && context.only === undefined) { // change cursor position
            const actions: CodeAction[] = []
            return {actions, dispose() {}}
        }*/
    }
})

// see https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-codelens-provider-example
// ex: https://code.visualstudio.com/docs/editor/editingevolved#_reference-information
export const codeLens = (opts: {} = {}): CodeLensProvider => ({ // hints with actions
    provideCodeLenses(model: ITextModel, token: CancellationToken): ProviderResult<CodeLensList> {
        // console.log('provideCodeLenses')
        const lenses: CodeLens[] = []
        return {lenses, dispose() {}}
    }
})

export const createMarker = (e: ParserError, model: ITextModel, editor: IStandaloneCodeEditor): IMarkerData => {
    const severity = e.level === 'error' ? MarkerSeverity.Error : e.level === 'warning' ? MarkerSeverity.Warning : e.level === 'info' ? MarkerSeverity.Info : MarkerSeverity.Hint
    if (e.position.start.line === 0 || e.position.start.column === 0) { // unknown position :/
        const cursor = editor.getPosition()
        return {
            message: e.message,
            severity,
            startLineNumber: cursor.lineNumber,
            startColumn: 1,
            endLineNumber: cursor.lineNumber,
            endColumn: cursor.column, // position until where to replace text, useful to replace a value on suggestion
        }
    } else {
        return {
            message: e.message,
            severity,
            startLineNumber: e.position.start.line,
            startColumn: e.position.start.column,
            endLineNumber: e.position.end.line,
            endColumn: e.position.end.column + 1,
        }
    }
}

// entity/attribute rename: ??? (https://code.visualstudio.com/docs/editor/editingevolved#_rename-symbol)
// go to definition: `{codeEditorService: {openCodeEditor: () => {}}}` as 3rd attr of `monaco.editor.create` (https://code.visualstudio.com/docs/editor/editingevolved#_go-to-definition & https://code.visualstudio.com/docs/editor/editingevolved#_peek)
// JSON defaults (json-schema validation for json editor: JSON to AML, help with Database json-schema): https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-configure-json-defaults
// folding provider (like markdown, fold between top level comments): https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-folding-provider-example
// hover provider (show definitions of entities/attrs in relations, show incoming relations in entities/attrs definitions): https://microsoft.github.io/monaco-editor/playground.html?source=v0.51.0#example-extending-language-services-hover-provider-example

// private helpers

// see https://microsoft.github.io/monaco-editor/typedoc/interfaces/languages.CompletionItem.html
function suggestText(text: string, kind: CompletionItemKind, position: Position, opts: {insert?: string, documentation?: string} = {}): CompletionItem {
    return {
        label: text.trim(),
        kind,
        insertText: opts.insert || text,
        range: {
            startLineNumber: position.lineNumber,
            startColumn: position.column,
            endLineNumber: position.lineNumber,
            endColumn: position.column,
        },
        documentation: opts.documentation,
    }
}

function suggestSnippet(label: string, completion: string, kind: CompletionItemKind, position: Position, opts: {documentation?: string} = {}): CompletionItem {
    return {
        label,
        kind,
        insertText: completion,
        insertTextRules: CompletionItemInsertTextRule.InsertAsSnippet,
        range: {
            startLineNumber: position.lineNumber,
            startColumn: position.column,
            endLineNumber: position.lineNumber,
            endColumn: position.column + completion.length,
        },
        ...opts
    }
}
