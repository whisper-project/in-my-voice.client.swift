# Whisper: conversation without voice

The Whisper app facilitates conversation where one of the participants (called the _Whisperer_) has difficulty speaking but not hearing, and the other participants (called _Listeners_) can speak to the Whisperer.  The Whisperer “speaks” by typing, and the Listeners “hear” that typing in real time.

## Design

The Whisper app uses a [simple entity model](#whisper-entities) to represent devices, users, and conversations. It uses a [simple data protocol](#whisper-protocol) to connect a Whisperer with Listeners. iOS and macOS devices running the Whisper app can establish conversations over Bluetooth LE without any internet connection, but for conversations with browser-based or remote Listeners the app relies on the [whisper server](#whisper-server) to provide coordination. 

### Whisper Entities

Whisper assigns each device that can whisper or listen a _device ID_ (which is a UUID).  iOS/macOS devices create their own device IDs, retain them in sandbox storage, and communicate them to the whisper server. Browsers are assigned device IDs by the whisper server and retain them in a long-lived cookie.

A whisper user is represented by a long-lived _profile_ entity, identified by a UUID.  A whisper profile stores the user’s chosen _username_, the list of conversations that the user has created as the Whisperer, and the list of conversations the the user has participated in as a Listener. Each generation of a device ID also generates a new profile entity which starts out as the user of that device.  However, existing profiles can be copied from one device to another, so that multiple devices can be used by the same user.  When different devices are using the same profile, they cooperate with the whisper server to make sure any profile updates made on one device are copied to all the others.

A whisper conversation is represented as a long-lived _conversation_ entity, identified by a UUID. Each conversation is created by a Whisperer. That Whisperer then controls which Listeners are allowed to join that conversation, and their profile IDs are kept in the conversation.  Whenever a user profile is created, it contains a default conversation for user to Whisper with, but that user can create new conversations and switch among them at will.

### Whisper Protocol

The whisper protocol is designed to work over a transport layer that provides:

1. point-to-point, sequenced delivery of packets in both directions,
2. two independent, simultaneous channels of conversation, each with its own authentcation, and
3. broadcasting packets from one source to all others.

The app currently supports two transport layers:

- Bluetooth LE connections (for local iOS/macOS Listeners), and
- the [Ably](https://ably.com) pub/sub realtime infrastructure (for remote or browser-based Listeners).

A single conversation can utilize both transports, with some Listeners on Bluetooth and others on Ably.

Establishment and teardown of connections between a Whisperer and Listeners takes place on one channel (called the _connection_ channel), and then content transfer from Whisperer to Listeners takes place on another channel (called the _content_) channel.  The separation of the two channels is what ensures that Listeners who aren’t authorized can’t eavesdrop on a conversation.

The protocol consists of packets sent from whisperer to listener or vice versa. (There is no listener-to-listener communication.) Each packet is a utf8-encoded string in three parts:

- a decimal integer packet type (called the _*offset*_ for historical reasons)
- a vertical bar '|' dividing the offset from the packet data
- the packet data itself

There are two kinds of packets: _*text*_ packets and _*control*_ packets:

- Text packets have offsets of 0 or greater: their packet data is text, and their offset indicates the position past which the packet text replaces the live text. If a listener receives an offset that's shorter than the live text, he can assume the user has revised earlier text. If a listener receives an offset that's longer than the live text, they can assume they’ve missed a packet and call for a full read of the live text, suspending incremental packet processing until the full data is received. Text packets are only transmitted on the content channel.
- Control packets have offsets less than 0, and the interpretation of their packet data depends on their offset. They can come at any point in the conversation.  Some of them are content-related and are sent on the content channel, others are connection-related and are sent on the connection channel.

To start a conversation, the Whisperer sends an _offer invite_ control packet on the connection channel, giving the conversation ID and the Whisperer’s device ID, profile ID, and username. Listeners who are present on that channel and want to join the conversation then send a _request invite_ control packet back to the Whisperer.  The Whisperer then sends authorized listeners an _accept invite_ control packet, and unauthorized listeners a _reject invite_ control packet.  Authorized listeners can then join the content channel.

Late-arriving Listeners who didn’t receive the _offer invite_ from the Whisperer can still send a _request invite_ packet when they join a conversation channel

### Whisper Server

The whisper server coordinates and secures all internet-based interactions between devices, including both internet-based conversations and the synchronization of profiles.    Whisper device IDs are tracked on the whisper server, where they are associated with all of the other entities used in the app’s operation on that device.

## License

All code and textual materials in this repository are copyright 2023 Daniel C. Brotsky, and licensed under the GNU Afero General Public License v3, which is reproduced in full in the [LICENSE](LICENSE) file.

The icon assets in this repository come from [the Noun Project](https://thenounproject.com), and are licensed via subscription by Daniel Brotsky for use in this application (see details [here](https://www.thenounproject.com/legal)).

The sound assets in this repository come from [Pixabay](https://pixabay.com), and are licensed by Daniel Brotsky for use in this application (see details [here](https://pixabay.com/service/license-summary/)).

## Acknowledgements

Daniel Brotsky gratefully acknowledges the following content creators whose materials are used in this application:

- [Whisper Speech Bubble Icon](https://thenounproject.com/icon/whisper-speech-bubble-4215124/) by [Lucas Helle](https://thenounproject.com/lucashelle/) via [the Noun Project](https://thenounproject.com).
- [Bicycle Bell Icon](https://thenounproject.com/icon/4355910/) by [DinosoftLab](https://thenounproject.com/dinosoftlab/) via [the Noun Project](https://thenounproject.com).
- [Bicycle Bell Sound](https://pixabay.com/sound-effects/bike-bell-100665/) by Yin Yang Jake007 from [Pixabay](https://pixabay.com).
- [Bicycle Horn Icon](https://thenounproject.com/icon/horn-2452403/) by [Berkah Icon](https://thenounproject.com/berkahicon/) via [the Noun Project](https://thenounproject.com).
- [Bicycle Horn Sound](https://pixabay.com/sound-effects/bicycle-horn-7126/) by AntumDeluge from [Pixabay](https://pixabay.com).
- [Air Horn Icon](https://thenounproject.com/icon/air-horn-4437429/) by [SuperNdre](https://thenounproject.com/pccandriaja13/) via [the Noun Project](https://thenounproject.com).
- [Air Horn Sound](https://pixabay.com/sound-effects/air-horn-close-and-loud-106073/) by goose278 from [Pixabay](https://pixabay.com).
- [Record Voice Over Icon](https://thenounproject.com/icon/record-voice-over-3644000/) by [Justin Blake](https://thenounproject.com/justin.blake.315/) via [the Noun Project](https://thenounproject.com).
- [Voice Over Off Icon](https://thenounproject.com/icon/voice-over-off-3644052/) by [Justin Blake](https://thenounproject.com/justin.blake.315/) via [the Noun Project](https://thenounproject.com).
- [Decrease Font Size Icon](https://thenounproject.com/icon/4866497/) by [Yeong Rong Kim](https://thenounproject.com/yeongrong.kim.5/) via [the Noun Project](https://thenounproject.com).
- [Increase Font Size Icon](https://thenounproject.com/icon/4866493/) by [Yeong Rong Kim](https://thenounproject.com/yeongrong.kim.5/) via [the Noun Project](https://thenounproject.com).

Daniel Brotsky is also grateful for the example application [ColorStripe](https://github.com/artemnovichkov/ColorStripe), designed by [@artemnovichkov](https://github.com/artemnovichkov) as described in his [blog post](https://blog.artemnovichkov.com/bluetooth-and-swiftui). Some of the code in ColorStripe, especially the use of Combine to connect Core Bluetooth managers with ViewModels, has been used in Whisper, as permitted by the [MIT license](https://github.com/artemnovichkov/ColorStripe/blob/main/LICENSE) under which ColorStripe was released.

