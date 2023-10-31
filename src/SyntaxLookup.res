module Category = {
  type t =
    | Decorators
    | Operators
    | LanguageConstructs
    | BuiltInFunctions
    | ExtensionPoints
    | SpecialValues
    | Other

  let toString = t =>
    switch t {
    | Decorators => "Decorators"
    | Operators => "Operators"
    | ExtensionPoints => "Extension Points"
    | BuiltInFunctions => "Built In Functions"
    | LanguageConstructs => "Language Constructs"
    | SpecialValues => "Special Values"
    | Other => "Other"
    }

  let fromString = (s: string): t => {
    switch s {
    | "decorators" => Decorators
    | "operators" => Operators
    | "languageconstructs" => LanguageConstructs
    | "builtinfunctions" => BuiltInFunctions
    | "extensionpoints" => ExtensionPoints
    | "specialvalues" => SpecialValues
    | _ => Other
    }
  }

  @react.component
  let make = (~title, ~children) => {
    <div>
      <h3 className="font-sans font-medium text-gray-100 tracking-wide text-14 uppercase mb-2">
        {React.string(title)}
      </h3>
      <div className="flex flex-wrap"> children </div>
    </div>
  }
}

// The data representing a syntax construct
// handled in the widget
type item = {
  id: string,
  keywords: array<string>,
  name: string,
  summary: string,
  category: Category.t,
  children: React.element,
}

type itemInfo = {
  id: string,
  keywords: array<string>,
  name: string,
  summary: string,
  category: Category.t,
}

let getAnchor = path => {
  switch Js.String2.split(path, "#") {
  | [_, anchor] => Some(anchor)
  | _ => None
  }
}

module Tag = {
  @react.component
  let make = (~text: string) => {
    <span className="hover:bg-fire hover:text-white bg-fire-5 py-1 px-3 rounded text-fire text-16">
      {React.string(text)}
    </span>
  }
}

module DetailBox = {
  @react.component
  let make = (~summary: string, ~children: React.element) => {
    let summaryEl = switch Js.String2.split(summary, "`") {
    | [] => React.null
    | [first, second, third] =>
      [
        React.string(first),
        <span className="text-fire"> {React.string(second)} </span>,
        React.string(third),
      ]
      ->Belt.Array.mapWithIndex((i, el) => {
        <span key={Belt.Int.toString(i)}> el </span>
      })
      ->React.array
    | more => Belt.Array.map(more, s => React.string(s))->React.array
    }

    <div>
      <div className="text-24 border-b border-gray-40 pb-4 mb-4 font-semibold"> summaryEl </div>
      <div className="mt-16"> children </div>
    </div>
  }
}

type state =
  | ShowAll
  | ShowFiltered(string, array<item>) // (search, filteredItems)
  | ShowDetails(item)

@val @scope("window")
external scrollTo: (int, int) => unit = "scrollTo"

let scrollToTop = () => scrollTo(0, 0)

type props = {mdxSources: array<MdxRemote.output>}
type params = {slug: string}

let decode = (json: Js.Json.t) => {
  switch json {
  | Object(itemDict) =>
    switch (
      itemDict->Js.Dict.get("id"),
      itemDict->Js.Dict.get("keywords"),
      itemDict->Js.Dict.get("name"),
      itemDict->Js.Dict.get("summary"),
      itemDict->Js.Dict.get("category"),
    ) {
    | (
        Some(String(id)),
        Some(Array(keywords)),
        Some(String(name)),
        Some(String(summary)),
        Some(String(category)),
      ) => {
        id,
        keywords: keywords->Belt.Array.keepMap(keyword => {
          switch keyword {
          | String(s) => s->Some
          | _ => None
          }
        }),
        name,
        summary,
        category: category->Category.fromString,
      }
    | _ => assert(false)
    }
  | _ => assert(false)
  }
}

let default = (props: props) => {
  let {mdxSources} = props

  let allItems = mdxSources->Js.Array2.map(mdxSource => {
    let {id, keywords, category, summary, name} = decode(mdxSource.frontmatter)

    let children =
      <MdxRemote
        frontmatter={mdxSource.frontmatter}
        compiledSource={mdxSource.compiledSource}
        scope={mdxSource.scope}
        components={MarkdownComponents.default}
      />

    {id, keywords, category, summary, name, children}
  })

  let fuseOpts = Fuse.Options.t(
    ~shouldSort=false,
    ~includeScore=true,
    ~threshold=0.2,
    ~location=0,
    ~distance=30,
    ~minMatchCharLength=1,
    ~keys=["keywords", "name"],
    (),
  )

  let fuse: Fuse.t<item> = Fuse.make(allItems, fuseOpts)

  let router = Next.Router.useRouter()
  let (state, setState) = React.useState(_ => ShowAll)

  let findItemById = id => allItems->Js.Array2.find(item => item.id === id)

  let findItemByExactName = name => allItems->Js.Array2.find(item => item.name === name)

  let searchItems = value =>
    fuse
    ->Fuse.search(value)
    ->Belt.Array.map(m => {
      m["item"]
    })

  // This effect is responsible for updating the view state when the router anchor changes.
  // This effect is triggered when:
  // [A] The page first loads.
  // [B] The search box is cleared.
  // [C] The search box value exactly matches an item name.
  React.useEffect(() => {
    switch getAnchor(router.asPath) {
    | None => setState(_ => ShowAll)
    | Some(anchor) =>
      switch findItemById(anchor) {
      | None => setState(_ => ShowAll)
      | Some(item) => {
          setState(_ => ShowDetails(item))
          scrollToTop()
        }
      }
    }
    None
  }, [router])

  // onSearchValueChange() is called when:
  // [A] The search value changes.
  // [B] The search is cleared.
  // [C] One of the tags is selected.
  //
  // We then handle three cases:
  // [1] Search is empty - trigger a route change, and allow the EFFECT to update the view state.
  // [2] Search exactly matches an item - trigger a route change, and allow the EFFECT to update the view state.
  // [3] Search does not match an item - immediately update the view state to show filtered items.
  let onSearchValueChange = value => {
    switch value {
    | "" => router->Next.Router.push("/syntax-lookup")
    | value =>
      switch findItemByExactName(value) {
      | None => {
          let filtered = searchItems(value)
          setState(_ => ShowFiltered(value, filtered))
        }

      | Some(item) => router->Next.Router.push("/syntax-lookup#" ++ item.id)
      }
    }
  }

  let details = switch state {
  | ShowFiltered(_, _)
  | ShowAll => React.null
  | ShowDetails(item) =>
    <div className="mb-16">
      <DetailBox summary={item.summary}> item.children </DetailBox>
    </div>
  }

  /*
    Order all items in tag groups
 */
  let categories = {
    open Category
    let initial = [
      Category.Decorators,
      Operators,
      LanguageConstructs,
      BuiltInFunctions,
      ExtensionPoints,
      SpecialValues,
      Other,
    ]->Belt.Array.map(cat => {
      (cat->toString, [])
    })

    let items = switch state {
    | ShowAll => allItems
    | ShowDetails(_) => []
    | ShowFiltered(_, items) => items
    }

    Belt.Array.reduce(items, Js.Dict.fromArray(initial), (acc, item) => {
      let key = item.category->toString
      Js.Dict.get(acc, key)->Belt.Option.mapWithDefault(acc, items => {
        Js.Array2.push(items, item)->ignore
        Js.Dict.set(acc, key, items)
        acc
      })
    })
    ->Js.Dict.entries
    ->Belt.Array.reduce([], (acc, entry) => {
      let (title, items) = entry
      if Js.Array.length(items) === 0 {
        acc
      } else {
        let children = Belt.Array.map(items, item => {
          let onMouseDown = evt => {
            ReactEvent.Mouse.preventDefault(evt)
            onSearchValueChange(item.name)
          }
          <span className="mr-2 mb-2 cursor-pointer" onMouseDown key=item.name>
            <Tag text={item.name} />
          </span>
        })
        let el =
          <div key=title className="first:mt-0 mt-12">
            <Category title> {React.array(children)} </Category>
          </div>
        Js.Array2.push(acc, el)->ignore
        acc
      }
    })
  }

  let (searchValue, completionItems) = switch state {
  | ShowFiltered(search, items) => (search, items)
  | ShowAll => ("", allItems)
  | ShowDetails(item) => (item.name, [item])
  }

  let onSearchClear = () => {
    onSearchValueChange("")
  }

  let overlayState = React.useState(() => false)
  let title = "Syntax Lookup | ReScript Documentation"

  let content =
    <div>
      <div className="flex flex-col items-center">
        <div className="text-center" style={ReactDOM.Style.make(~maxWidth="21rem", ())}>
          <Markdown.H1> {React.string("Syntax Lookup")} </Markdown.H1>
          <div className="mb-8 text-gray-60-tr text-14">
            {React.string("Enter some language construct you want to know more about.")}
          </div>
        </div>
        <div className="w-full" style={ReactDOM.Style.make(~maxWidth="34rem", ())}>
          <SearchBox
            placeholder="Enter keywords or syntax..."
            completionValues={Belt.Array.map(completionItems, item => item.name)}
            value=searchValue
            onClear=onSearchClear
            onValueChange=onSearchValueChange
          />
        </div>
      </div>
      <div className="mt-10">
        {details}
        {React.array(categories)}
      </div>
    </div>

  <>
    <Meta
      siteName="ReScript Syntax Lookup"
      title
      description="Discover ReScript syntax constructs with our lookup tool"
    />
    <div className="mt-4 xs:mt-16">
      <div className="text-gray-80">
        <Navigation overlayState />
        <div className="flex xs:justify-center overflow-hidden pb-48">
          <main className="mt-16 min-w-320 lg:align-center w-full px-4 md:px-8 max-w-1280">
            <MdxProvider components=MarkdownComponents.default>
              <div className="flex justify-center">
                <div className="max-w-740 w-full"> content </div>
              </div>
            </MdxProvider>
          </main>
        </div>
        <Footer />
      </div>
    </div>
  </>
}

let getStaticProps: Next.GetStaticProps.t<props, params> = async _ctx => {
  let dir = Node.Path.resolve("misc_docs", "syntax")

  let allFiles = Node.Fs.readdirSync(dir)->Js.Array2.map(async file => {
    let fullPath = Node.Path.join2(dir, file)
    let source = fullPath->Node.Fs.readFileSync
    await MdxRemote.serialize(
      source,
      {parseFrontmatter: true, mdxOptions: MdxRemote.defaultMdxOptions},
    )
  })

  let mdxSources = await Js.Promise2.all(allFiles)

  {"props": {mdxSources: mdxSources}}
}
