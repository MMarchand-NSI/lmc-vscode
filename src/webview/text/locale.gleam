//// Le choix de la langue, pour le panneau.
////
//// **Le seul endroit à toucher pour ajouter une langue** : un bras dans
//// chaque `case` ci-dessous. Le compilateur réclame alors le fichier
//// manquant, et aucune traduction existante n'est modifiée. Même forme que
//// `lmc/text/locale.gleam` dans `lmc_lsp`, exprès.
////
//// Le type `Locale` lui-même n'est pas redéfini ici : c'est celui du
//// serveur. Deux définitions laisseraient le panneau et les diagnostics
//// répondre différemment au même réglage, et `server.render` s'appelle
//// ainsi avec la même valeur, sans conversion.

import gleam/list
import lmc/runner/load
import lmc/text/locale as server
import webview/text/english
import webview/text/french
import webview/text/message.{type Label, type Phase, type Text}
import webview/text/spanish

pub type Locale =
  server.Locale

/// Le français, comme côté serveur : un panneau muet est plus probablement
/// une classe qu'un anglophone.
pub const default_locale = server.default_locale

/// `fr`, `fr-FR`, `en-GB`… La lecture est celle du serveur, appelée et non
/// réécrite : deux lectures du même réglage le feraient répondre de deux
/// façons.
pub fn from_tag(tag: String) -> Locale {
  server.from_tag(tag)
}

pub fn render(text: Text, language: Locale) -> String {
  case language {
    server.French -> french.render(text)
    server.English -> english.render(text)
    server.Spanish -> spanish.render(text)
  }
}

pub fn label(label: Label, language: Locale) -> String {
  case language {
    server.French -> french.label(label)
    server.English -> english.label(label)
    server.Spanish -> spanish.label(label)
  }
}

/// Seule la phase d'erreur dépend de la langue : « Fetch », « Decode » et
/// « Execute » sont les termes du cours, employés tels quels partout.
pub fn phase_label(phase: Phase, language: Locale) -> String {
  case phase {
    message.Fetch -> "Fetch"
    message.Decode -> "Decode"
    message.Execute -> "Execute"
    message.Failure ->
      case language {
        server.French -> "Erreur"
        server.English -> "Error"
        server.Spanish -> "Error"
      }
  }
}

/// L'étiquette BCP 47 de la langue rendue, pour l'attribut `lang` du
/// document : la césure et les lecteurs d'écran s'en servent.
pub fn tag(language: Locale) -> String {
  case language {
    server.French -> "fr"
    server.English -> "en"
    server.Spanish -> "es"
  }
}

/// Toutes les étiquettes du décor, prêtes à être posées dans le DOM.
pub fn labels(language: Locale) -> List(#(String, String)) {
  message.label_keys()
  |> list.map(fn(pair) { #(pair.0, label(pair.1, language)) })
}

/// L'échec du chargeur, tel qu'il se dira à l'écran.
pub fn load_error(err: load.LoadError) -> Text {
  message.load_error(err)
}
