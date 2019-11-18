import 'package:built_collection/built_collection.dart';
import 'package:rebloc/rebloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tailor_made/dependencies.dart';
import 'package:tailor_made/models/contact.dart';
import 'package:tailor_made/rebloc/app_state.dart';
import 'package:tailor_made/rebloc/common/actions.dart';
import 'package:tailor_made/rebloc/contacts/actions.dart';
import 'package:tailor_made/rebloc/contacts/sort_type.dart';

class ContactsBloc extends SimpleBloc<AppState> {
  @override
  Stream<WareContext<AppState>> applyMiddleware(Stream<WareContext<AppState>> input) {
    MergeStream([
      Observable(input).where((context) => context.action is SearchContactAction).switchMap(_makeSearch),
      Observable(input).where((context) => context.action is InitContactsAction).switchMap(_onAfterLogin),
    ])
        .takeWhile((context) => context.action is! OnDisposeAction)
        .listen((context) => context.dispatcher(context.action));

    return input;
  }

  @override
  AppState reducer(AppState state, Action action) {
    final _contacts = state.contacts;

    if (action is OnDataAction<List<ContactModel>>) {
      return state.rebuild(
        (b) => b
          ..contacts = _contacts
              .rebuild(
                (b) => b
                  ..contacts = BuiltList<ContactModel>.of(action.payload..sort(_sort(_contacts.sortFn))).toBuilder()
                  ..status = StateStatus.success,
              )
              .toBuilder(),
      );
    }

    if (action is StartSearchContactAction) {
      return state.rebuild(
        (b) => b
          ..contacts = _contacts
              .rebuild((b) => b
                ..status = StateStatus.loading
                ..isSearching = true)
              .toBuilder(),
      );
    }

    if (action is SearchSuccessContactAction) {
      return state.rebuild(
        (b) => b
          ..contacts = _contacts
              .rebuild(
                (b) => b
                  ..searchResults =
                      BuiltList<ContactModel>.of(action.payload..sort(_sort(_contacts.sortFn))).toBuilder()
                  ..status = StateStatus.success,
              )
              .toBuilder(),
      );
    }

    if (action is SortContacts) {
      return state.rebuild(
        (b) => b
          ..contacts = _contacts
              .rebuild(
                (b) => b
                  ..contacts =
                      BuiltList<ContactModel>.of(_contacts.contacts.toList()..sort(_sort(action.payload))).toBuilder()
                  ..hasSortFn = action.payload != SortType.reset
                  ..sortFn = action.payload
                  ..status = StateStatus.success,
              )
              .toBuilder(),
      );
    }

    if (action is CancelSearchContactAction) {
      return state.rebuild(
        (b) => b
          ..contacts = _contacts
              .rebuild((b) => b
                ..status = StateStatus.success
                ..isSearching = false
                ..searchResults = BuiltList<ContactModel>(<ContactModel>[]).toBuilder())
              .toBuilder(),
      );
    }

    return state;
  }
}

Comparator<ContactModel> _sort(SortType sortType) {
  switch (sortType) {
    case SortType.jobs:
      {
        return (a, b) => b.totalJobs.compareTo(a.totalJobs);
      }
    case SortType.names:
      {
        return (a, b) => a.fullname.compareTo(b.fullname);
      }
    case SortType.completed:
      {
        return (a, b) => (b.totalJobs - b.pendingJobs).compareTo(a.totalJobs - a.pendingJobs);
      }
    case SortType.pending:
      {
        return (a, b) => b.pendingJobs.compareTo(a.pendingJobs);
      }
    case SortType.recent:
      {
        return (a, b) => b.createdAt.compareTo(a.createdAt);
      }
    case SortType.reset:
    default:
      {
        return (a, b) => a.id.compareTo(b.id);
      }
  }
}

Stream<WareContext<AppState>> _onAfterLogin(WareContext<AppState> context) {
  return Dependencies.di()
      .contacts
      .fetchAll(Dependencies.di().session.user.getId())
      .map((contacts) => OnDataAction<List<ContactModel>>(payload: contacts))
      .map((action) => context.copyWith(action));
}

Stream<WareContext<AppState>> _makeSearch(WareContext<AppState> context) {
  return Observable<String>.just((context.action as SearchContactAction).payload)
      .doOnData((_) => context.dispatcher(const StartSearchContactAction()))
      .map<String>((String text) => text.trim())
      .distinct()
      .where((text) => text.length > 1)
      .debounceTime(const Duration(milliseconds: 750))
      .map((text) => SearchSuccessContactAction(
            payload: context.state.contacts.contacts
                .where((contact) => contact.fullname.contains(RegExp(r'' + text + '', caseSensitive: false)))
                .toList(),
          ))
      .takeWhile((action) => action is! CancelSearchContactAction)
      .map((action) => context.copyWith(action));
}
