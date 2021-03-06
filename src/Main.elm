port module Main exposing (main)

import Browser
import Cmd.Extra exposing (addCmd, addCmds, withCmd, withCmds, withNoCmd)
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h1, input, p, span, text)
import Html.Attributes exposing (checked, disabled, href, size, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Encode as JE exposing (Value)
import Json.Decode as JD exposing (Decoder, field, map2, list, string, Error)
import PortFunnel.WebSocket as WebSocket exposing (Response(..))
import PortFunnel.LocalStorage as LocalStorage
    exposing
        ( Key
        , Message
        , Response(..)
        )
import PortFunnels exposing (FunnelDict, Handler(..), State)



{- This section contains boilerplate that you'll always need.

   First, copy PortFunnels.elm into your project, and modify it
   to support all the funnel modules you use.

   Then update the `handlers` list with an entry for each funnel.

   Those handler functions are the meat of your interaction with each
   funnel module.
-}

type alias Message = 
  { origin: String
  , message: String
  }

messageDecoder : Decoder Message
messageDecoder =
  map2 Message
    (field "origin" string)
    (field "message" string)

handlers : List (Handler Model Msg)
handlers =
    [ WebSocketHandler socketHandler
    , LocalStorageHandler storageHandler
    ]


subscriptions : Model -> Sub Msg
subscriptions =
    PortFunnels.subscriptions Process


funnelDict : FunnelDict Model Msg
funnelDict =
    PortFunnels.makeFunnelDict handlers getCmdPort


{-| Get a possibly simulated output port.
-}
getCmdPort : String -> Model -> (Value -> Cmd Msg)
getCmdPort moduleName model =
    PortFunnels.getCmdPort Process moduleName False


{-| The real output port.
-}
cmdPort : Value -> Cmd Msg
cmdPort =
    PortFunnels.getCmdPort Process "" False



-- MODEL


defaultUrl : String
defaultUrl =
    "ws://localhost:1234/chat"


type alias Model =
    { send : String
    , log : List String
    , messages : List Message
    , url : String
    , wasLoaded : Bool
    , state : State
    , key : String
    , error : Maybe String
    , keyLs : Key
    , value : String
    , label : String
    , returnLabel : String
    , keysString : String
    }


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }

prefix : String
prefix =
    "example"

init : () -> ( Model, Cmd Msg )
init _ =
    { send = "Hello World!"
    , log = []
    , messages = []
    , url = defaultUrl
    , wasLoaded = False
    , state = PortFunnels.initialState prefix
    , key = "socket"
    , error = Nothing
    , keyLs = "key"
    , value = ""
    , label = ""
    , returnLabel = ""
    , keysString = ""
    }
        |> withNoCmd



-- UPDATE


type Msg
    = UpdateSend String
    | UpdateUrl String
    | Connect
    | Close
    | Send
    | SetUrl
    | GetUrl
    | Process Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend newsend ->
            { model | send = newsend } |> withNoCmd
        SetUrl ->
          model |> withCmd
              (sendLs
                (LocalStorage.put "url"
                    (Just <| JE.string model.url)
                )
                model
              )

        GetUrl -> 
          let message = LocalStorage.get "url" in
          model |> withCmd (sendLs message model)

        UpdateUrl url ->
            { model | url = url } |> withNoCmd

        Connect ->
            { model
                | log =
                    ("Connecting to " ++ model.url) :: model.log
            }
                |> withCmd
                    (WebSocket.makeOpenWithKey model.key model.url
                        |> send model
                    )

        Send -> model
                |> withCmd
                    (WebSocket.makeSend model.key model.send
                        |> send model
                    )

        Close ->
            { model
                | log = "Closing" :: model.log
            }
                |> withCmd
                    (WebSocket.makeClose model.key
                        |> send model
                    )

        Process value ->
            case
                PortFunnels.processValue funnelDict value model.state model
            of
                Err error ->
                    { model | error = Just error } |> withNoCmd

                Ok res ->
                    res


send : Model -> WebSocket.Message -> Cmd Msg
send model message =
    WebSocket.send (getCmdPort WebSocket.moduleName model) message


sendLs : LocalStorage.Message -> Model -> Cmd Msg
sendLs message model =
    LocalStorage.send (getCmdPort LocalStorage.moduleName model)
        message
        model.state.storage

doIsLoaded : Model -> Model
doIsLoaded model =
    if not model.wasLoaded && WebSocket.isLoaded model.state.websocket then
        { model
            | wasLoaded = True
        }

    else
        model


storageHandler : LocalStorage.Response -> PortFunnels.State -> Model -> ( Model, Cmd Msg )
storageHandler response state mdl =
    let
        model =
            doIsLoaded
                { mdl | state = state }
    in
    case response of
        LocalStorage.GetResponse { label, key, value } ->
            let
                string =
                    case value of
                        Nothing ->
                            "<null>"

                        Just v ->
                            decodeString v
            in
            { model | url = string } |> withNoCmd

        _ ->
            model |> withNoCmd

decodeString : Value -> String
decodeString value =
    case JD.decodeValue JD.string value of
        Ok res ->
            res

        Err err ->
            JD.errorToString err

defaultMessage: List Message
defaultMessage =  
  [{ message = "no luck", origin = "server"}]
 
socketHandler : WebSocket.Response -> State -> Model -> ( Model, Cmd Msg )
socketHandler response state mdl =
    let
        model =
            doIsLoaded
                { mdl
                    | state = state
                    , error = Nothing
                }
    in
    case response of
        WebSocket.MessageReceivedResponse { message } ->
            { model | messages = (JD.decodeString (list messageDecoder) message) |> Result.withDefault defaultMessage   }
                |> withNoCmd

        WebSocket.ConnectedResponse r ->
            { model | log = ("Connected: " ++ r.description) :: model.log }
                |> withNoCmd

        WebSocket.ClosedResponse { code, wasClean, expected } ->
            { model
                | log =
                    ("Closed, " ++ closedString code wasClean expected)
                        :: model.log
            }
                |> withNoCmd

        WebSocket.ErrorResponse error ->
            { model | log = WebSocket.errorToString error :: model.log }
                |> withNoCmd

        _ ->
            case WebSocket.reconnectedResponses response of
                [] ->
                    model |> withNoCmd

                [ ReconnectedResponse r ] ->
                    { model | log = ("Reconnected: " ++ r.description) :: model.log }
                        |> withNoCmd

                list ->
                    { model | log = Debug.toString list :: model.log }
                        |> withNoCmd
                        
stringListToString : List String -> String
stringListToString list =
    let
        quoted =
            List.map (\s -> "\"" ++ s ++ "\"") list

        commas =
            List.intersperse ", " quoted
                |> String.concat
    in
    "[" ++ commas ++ "]"


closedString : WebSocket.ClosedCode -> Bool -> Bool -> String
closedString code wasClean expected =
    "code: "
        ++ WebSocket.closedCodeToString code
        ++ ", "
        ++ (if wasClean then
                "clean"

            else
                "not clean"
           )
        ++ ", "
        ++ (if expected then
                "expected"

            else
                "NOT expected"
           )



-- VIEW


b : String -> Html Msg
b string =
    Html.b [] [ text string ]


br : Html msg
br =
    Html.br [] []


docp : String -> Html Msg
docp string =
    p [] [ text string ]


view : Model -> Html Msg
view model =
    let
        isConnected =
            WebSocket.isConnected model.key model.state.websocket
    in
    div
        [ style "width" "40em"
        , style "margin" "auto"
        , style "margin-top" "1em"
        , style "padding" "1em"
        , style "border" "solid"
        ]
        [ h1 [] [ text "WebSocket and LocalStorage via PortFunnel" ]
        , p []
            [ b "url: "
            , input
                [ value model.url
                , onInput UpdateUrl
                , size 30
                , disabled isConnected
                ]
                []
            , text " "
            , if isConnected then
                button [ onClick Close ]
                    [ text "Close" ]

              else
                button [ onClick Connect ]
                    [ text "Connect" ]
            , button [onClick SetUrl] [text "Save Url"]
            , button [onClick GetUrl] [text "Restore Url"]
            ]
        , p [] <|
            List.concat
                [ [ b "log:"
                  , br
                  ]
                , List.intersperse br (List.map text model.log)
                ]
        , p [] <|
            List.concat
                [ [ b "Chat:"
                  , br
                  ]
                , List.intersperse br (List.map renderMessage model.messages)
                ]
        , p []
            [ input
                [ value model.send
                , onInput UpdateSend
                , size 50
                ]
                []
            , text " "
            , button
                [ onClick Send
                , disabled (not isConnected)
                ]
                [ text "Send" ]
            ]
        ]

renderMessage: Message -> Html Msg
renderMessage message = 
    div [] 
      [ b message.origin
      , span [] [text " :: "]
      , span [] [text message.message]
      ]