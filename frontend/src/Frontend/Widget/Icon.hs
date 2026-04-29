-- | Heroicons (MIT, https://heroicons.com/) inlined as SVG. One function
-- per icon — only the icons referenced by call sites end up in the bundle.
-- Path data copied verbatim from the @24/outline@ set; @stroke@ is changed
-- to @currentColor@ so each icon takes its colour from the surrounding
-- button's text colour. To add a new icon: copy its SVG from heroicons.com,
-- paste the @d@ attribute below, give the function a name.
{-# LANGUAGE FlexibleContexts #-}

module Frontend.Widget.Icon
  ( iconArrowRightEndOnRectangle
  , iconArrowLeftStartOnRectangle
  , iconCheckCircle
  , iconExclamationTriangle
  , iconUserPlus
  ) where

import Reflex.Dom.Core
  ( DomBuilder
  , PostBuild
  , blank
  , constDyn
  , elDynAttrNS
  , (=:)
  )
import Relude

svgNs :: Maybe Text
svgNs = Just "http://www.w3.org/2000/svg"

svgEl
  :: (DomBuilder t m, PostBuild t m)
  => Text -> Map Text Text -> m a -> m a
svgEl tag attrs = elDynAttrNS svgNs tag (constDyn attrs)

-- | Shared SVG attributes for every outline icon. @size-5@ gives a
-- 1.25rem square that pairs with daisyUI's default button text size.
outlineAttrs :: Map Text Text
outlineAttrs =
       "viewBox"           =: "0 0 24 24"
    <> "fill"              =: "none"
    <> "stroke"            =: "currentColor"
    <> "stroke-width"      =: "1.5"
    <> "stroke-linecap"    =: "round"
    <> "stroke-linejoin"   =: "round"
    <> "class"             =: "size-5"
    <> "aria-hidden"       =: "true"

outlineIcon
  :: (DomBuilder t m, PostBuild t m)
  => Text -> m ()
outlineIcon d = svgEl "svg" outlineAttrs $ svgEl "path" ("d" =: d) blank

-- | Arrow into a box — used for "Sign in".
iconArrowRightEndOnRectangle :: (DomBuilder t m, PostBuild t m) => m ()
iconArrowRightEndOnRectangle = outlineIcon
  "M8.25 9V5.25C8.25 4.00736 9.25736 3 10.5 3L16.5 3C17.7426 3 18.75 4.00736 18.75 5.25L18.75 18.75C18.75 19.9926 17.7426 21 16.5 21H10.5C9.25736 21 8.25 19.9926 8.25 18.75V15M12 9L15 12M15 12L12 15M15 12L2.25 12"

-- | Arrow out of a box — used for "Log out".
iconArrowLeftStartOnRectangle :: (DomBuilder t m, PostBuild t m) => m ()
iconArrowLeftStartOnRectangle = outlineIcon
  "M8.25 9V5.25C8.25 4.00736 9.25736 3 10.5 3H16.5C17.7426 3 18.75 4.00736 18.75 5.25V18.75C18.75 19.9926 17.7426 21 16.5 21H10.5C9.25736 21 8.25 19.9926 8.25 18.75V15M5.25 15L2.25 12M2.25 12L5.25 9M2.25 12L15 12"

-- | User silhouette with a plus — used for "Create account".
iconUserPlus :: (DomBuilder t m, PostBuild t m) => m ()
iconUserPlus = outlineIcon
  "M18 7.5V10.5M18 10.5V13.5M18 10.5H21M18 10.5H15M12.75 6.375C12.75 8.23896 11.239 9.75 9.375 9.75C7.51104 9.75 6 8.23896 6 6.375C6 4.51104 7.51104 3 9.375 3C11.239 3 12.75 4.51104 12.75 6.375ZM3.00092 19.2343C3.00031 19.198 3 19.1615 3 19.125C3 15.6042 5.85418 12.75 9.375 12.75C12.8958 12.75 15.75 15.6042 15.75 19.125V19.1276C15.75 19.1632 15.7497 19.1988 15.7491 19.2343C13.8874 20.3552 11.7065 21 9.375 21C7.04353 21 4.86264 20.3552 3.00092 19.2343Z"

-- | Circled check — used inside @alert-success@ toasts.
iconCheckCircle :: (DomBuilder t m, PostBuild t m) => m ()
iconCheckCircle = outlineIcon
  "M9 12.75L11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"

-- | Warning triangle with exclamation mark — used inside @alert-error@ toasts.
iconExclamationTriangle :: (DomBuilder t m, PostBuild t m) => m ()
iconExclamationTriangle = outlineIcon
  "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
