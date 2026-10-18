#ifndef MEDUSA_CORE_AC_AUTOFILL_TRIGGER_H_
#define MEDUSA_CORE_AC_AUTOFILL_TRIGGER_H_

namespace content {
class WebContents;
}

namespace medusacore {

void TrackAutofillFocus(content::WebContents* contents);
bool ShowAutofillSuggestions(content::WebContents* contents, bool passwords);

}

#endif
