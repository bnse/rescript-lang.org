let apiKey = "d3d9d7cebf13a7b665e47cb85dc9c582"
let indexName = "rescript-lang"
let appId = "BH4D9OD16A"

@val @scope("document")
external activeElement: option<Dom.element> = "activeElement"

type keyboardEventLike = {key: string, ctrlKey: bool, metaKey: bool}
@val @scope("window")
external addKeyboardEventListener: (string, keyboardEventLike => unit) => unit = "addEventListener"

@val @scope("window")
external removeKeyboardEventListener: (string, keyboardEventLike => unit) => unit =
  "addEventListener"

type window
@val external window: window = "window"
@get external scrollY: window => int = "scrollY"

@send
external keyboardEventPreventDefault: keyboardEventLike => unit = "preventDefault"

@get external tagName: Dom.element => string = "tagName"
@get external isContentEditable: Dom.element => bool = "isContentEditable"

type state = Active | Inactive

@react.component
let make = () => {
  let (state, setState) = React.useState(_ => Inactive)

  React.useEffect1(() => {
    let isEditableTag = el =>
      switch el->tagName {
      | "TEXTAREA" | "SELECT" | "INPUT" => true
      | _ => false
      }

    let focusSearch = e => {
      switch activeElement {
      | Some(el) if el->isEditableTag || el->isContentEditable => ()
      | _ =>
        setState(_ => Active)
        e->keyboardEventPreventDefault
      }
    }

    let handleGlobalKeyDown = e => {
      switch e.key {
      | "/" => focusSearch(e)
      | "k" if e.ctrlKey || e.metaKey => focusSearch(e)
      | "Escape" => setState(_ => Inactive)
      | _ => ()
      }
    }
    addKeyboardEventListener("keydown", handleGlobalKeyDown)
    Some(() => removeKeyboardEventListener("keydown", handleGlobalKeyDown))
  }, [setState])

  let onClick = _ => setState(_ => Active)

  let onClose = React.useCallback1(() => {
    setState(_ => Inactive)
  }, [setState])

  <>
    <button onClick type_="button" className="text-gray-60 hover:text-fire-50 p-2">
      <Icon.MagnifierGlass className="fill-current" />
    </button>
    {switch state {
    | Active =>
      switch ReactDOM.querySelector("body") {
      | Some(element) =>
        ReactDOM.createPortal(
          <DocSearch
            apiKey
            appId
            indexName
            onClose
            initialScrollY={window->scrollY}
            transformItems={items => {
              // Js.log(items)
              // Transform absolute URL intro relative url
              items->Js.Array2.map(item => {
                let url = try Util.Url.make(item.url).pathname catch {
                | Js.Exn.Error(obj) =>
                  switch Js.Exn.message(obj) {
                  | Some(m) =>
                    Js.Console.error("Failed to constructor URL " ++ m)
                    item.url
                  | None => item.url
                  }
                }

                let (content, type_) = switch item.content->Js.Nullable.toOption {
                | Some(c) => (c->Js.Nullable.return, item.type_)
                | None =>
                  let fallback = item.hierarchy.lvl0
                  (fallback->Js.Nullable.return, #content)
                }

                {...item, url, content, type_}
              })
            }}
            hitComponent={({hit, children}) => {
              let description = switch hit.url
              ->Js.String2.split("/")
              ->Js.Array2.sliceFrom(1)
              ->Belt.List.fromArray {
              | list{"blog", ..._} => "BLOG"
              | list{"docs", "manual", version, ...rest} =>
                let path = rest->Belt.List.toArray

                let info =
                  path
                  ->Js.Array2.slice(~start=0, ~end_=Js.Array2.length(path) - 1)
                  ->Js.Array2.map(Js.String2.toUpperCase)

                let version = if version == "latest" {
                  "Latest"
                } else {
                  version
                }

                [version]->Js.Array2.concat(info)->Js.Array2.joinWith(" / ")
              | _ => ""
              }
              // <div className="flex flex-col w-full">
              <a href={hit.url} className="flex flex-col w-full">
                <span className="text-gray-60 captions px-4 py-2 block">
                  {description->React.string}
                </span>
                children
              </a>
              // </div>
            }}
          />,
          element,
        )
      | None => React.null
      }
    | Inactive => React.null
    }}
  </>
}
