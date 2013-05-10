#ifndef REGISTER_H
#define REGISTER_H

/*
 * Interface to register stuff for the lua plugins. Capabilities,
 * namespaces and callbacks.
 */

/*
 * Add a capability to the list in the <hello> message.
 *
 * The cap_uri is the uri to include there, even if the name sounds like a fish.
 */
void register_capability(const char *cap_uri);

#endif
