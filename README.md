# Whisper: conversation without voice

The Whisper app facilitates conversation where one of the participants (called the _Whisperer_) has difficulty speaking but not hearing, and the other participants (called _Listeners_) can speak to the Whisperer.  The Whisperer “speaks” by typing, and the Listeners “hear” that typing in real time.

## Design

The Whisper app uses a [simple entity model](#whisper-entities) to represent devices, users, and conversations. It uses a [simple data protocol](#whisper-protocol) to connect a Whisperer with Listeners. iOS and macOS devices running the Whisper app can establish conversations over Bluetooth LE without any internet connection, but for conversations with browser-based or remote Listeners the app relies on the [whisper server](#whisper-server) to provide coordination. 

### Whisper Entities

Whisper assigns each device that can whisper or listen a _device ID_ (which is a UUID).  iOS/macOS devices create their own device IDs, retain them in sandbox storage, and communicate them to the whisper server. Browsers are assigned device IDs by the whisper server and retain them in a long-lived cookie.

A whisper user is represented by a long-lived _profile_ entity, identified by a UUID.  A whisper profile stores the user’s chosen _username_, the list of conversations that the user has created as the Whisperer, and the list of conversations that the user has participated in as a Listener. Each generation of a device ID also generates a new profile entity which starts out as the user profile in use on that device.  However, existing devices can elect to use the profile shared from another device, so that multiple devices can be used by the same user.  When different devices are using the same profile, they cooperate with the whisper server to make sure any profile updates made on one device are also made on the others.

A whisper conversation is represented as a long-lived _conversation_ entity, identified by a UUID. Each conversation is created by a Whisperer. That Whisperer then controls which Listeners are allowed to join that conversation, and their profile IDs are kept in the conversation.  Whenever a user profile is created, it contains a default conversation for the user to Whisper with, but that user can create new conversations and switch among them at will.

### Whisper Protocol

The whisper protocol consists of packets, typically very small, sent from whisperer to listener or vice versa. (There is no listener-to-listener communication.) Each packet is a utf8-encoded string in three parts:

- a decimal integer packet type (called the _*offset*_ for historical reasons)
- a vertical bar '|' dividing the offset from the packet data
- the packet data itself

There are two kinds of packets: _*text*_ packets and _*control*_ packets:

- Text packets are used to send changes in the Whisperer’s live text. They have offsets of 0 or greater, and their packet data is text. Their offset indicates the position past which the packet text replaces the live text. If a listener receives an offset that's shorter than the live text, he can assume the user has revised earlier text. If a listener receives an offset that's longer than the live text, they can assume they’ve missed a packet and call for a re-read of the live text, suspending incremental text packet processing until the full data is received.
- Control packets have offsets less than 0, and the interpretation of their packet data depends on their offset. Some of them are used to carry textual changes, such as shifting the live text to past text when the Whisperer hits return. Others are used for connection control, such as authorization handshakes.

The whisper protocol is designed to work over a transport layer that provides:

1. peer-to-peer, point-to-point or broadcast, sequenced delivery of packets, and
2. two independent, simultaneous channels, each with its own authentication.

The app currently supports two transport layers:

- Bluetooth LE connections (for local iOS/macOS Listeners), and
- the [Ably](https://ably.com) pub/sub realtime infrastructure (for remote or browser-based Listeners).

A single conversation can utilize both transports, with some Listeners on Bluetooth and others on Ably.

Establishment and teardown of connections between a Whisperer and Listeners takes place on one channel (called the _control_ channel), and then content transfer from Whisperer to Listeners takes place on another channel (called the _content_ channel).  The separate authentication of the two channels is used to prevent Listeners who aren’t authorized from eavesdropping on a conversation.

The canonical sequence for establishing a new conversation between a Whisperer and a Listener goes as follows:

1. The Listener sends the Whisperer a _listen offer_ packet on the control channel.  This packet contains the listener’s profile ID but reveals nothing about the listener’s username.
2. The Whisperer sends the Listener a *whisper offer* packet on the control channel. This contains the id and name of the conversation being offered as well as the Whisperer’s profile id and username.
3. The Listener decides based on the offer information whether they want to participate in the conversation.  If they do, they respond with a *listen request* packet, giving their profile id and name.
4. The Whisperer sees the _listen request_ packet and decides based on the request information whether they want to allow the Listener into the conversation:
   1. If so, the Whisperer authorizes the Listener on the content channel and sends a _listen authorization_ packet.
   2. If not, the Whisperer sends a _listen deauthorization_ packet.

5. If the Listener receives a _listen authorization_ packet, they connect to the content channel and send a _joining_ message on the conversation channel.

Because a Whisperer can recognize an existing listener from their _listen offer_ packet, the canonical sequence for a Listener re-joining a conversation to which they were already admitted is just steps 1, 4.1, and 5 from the above sequence.

Whenever a Whisperer drops from a conversation, they send a _dropping_ packet to let the Listeners know, and vice versa (Listeners who drop send a _dropping_ packet to the Whisperer).

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

