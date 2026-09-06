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
import webview/text/japanese
import webview/text/korean
import webview/text/message.{type Label, type Phase, type Text}
import webview/text/spanish

pub type Locale =
  server.Locale

/// La langue du tout premier affichage, avant que l'hôte n'ait dit laquelle
/// il veut.
///
/// **Un défaut et un repli sont deux choses**, et depuis la v0.8.2 du
/// serveur elles ne coïncident plus. Le repli répond « je ne parle pas ce
/// que tu demandes » et vaut l'anglais, la langue qu'un lecteur venu
/// d'ailleurs a le plus de chances de comprendre : c'est
/// `server.default_locale`, et `from_tag` s'en sert. Le défaut répond « tu
/// n'as rien demandé » et vaut le français, parce que c'est ce que le
/// réglage `lmc.locale` enverra une milliseconde plus tard. Prendre le
/// repli ici ferait clignoter le panneau en anglais avant le premier
/// `setLocale`.
pub const default_locale = server.French

/// Le repli, tel que le serveur le définit. Distinct du défaut ci-dessus.
pub const fallback_locale = server.default_locale

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
    server.Japanese -> japanese.render(text)
    server.Korean -> korean.render(text)
  }
}

pub fn label(label: Label, language: Locale) -> String {
  case language {
    server.French -> french.label(label)
    server.English -> english.label(label)
    server.Spanish -> spanish.label(label)
    server.Japanese -> japanese.label(label)
    server.Korean -> korean.label(label)
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
        server.Japanese -> "エラー"
        server.Korean -> "오류"
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
    server.Japanese -> "ja"
    server.Korean -> "ko"
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
