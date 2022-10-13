-module(erlflow_utils).
-author("losto").

%% API
-export([
    from_list_recursive/1,
    to_binary/1
]).


-spec from_list_recursive(Data :: list(list(tuple())) | list(tuple()) | map()) -> Result :: list(map()).

from_list_recursive([List|_] = ListOfLists) when is_list(List) ->
    lists:foldr(fun(L, Acc) -> [from_list_recursive(maps:from_list(L)) | Acc] end, [], ListOfLists);

from_list_recursive(List) when is_list(List) ->
    [from_list_recursive(maps:from_list(List))];

from_list_recursive(Map) ->
    maps:fold(fun
                  (K, [V|_] = ListOfLists, Acc) when is_list(V) ->
                      MaybeMapped = internal_recursive(lists:reverse(ListOfLists)),
                      Acc#{K => MaybeMapped};
                  (K, V, Acc) when is_list(V) ->
                      MaybeMapped = try maps:from_list(V) of
                                        M -> from_list_recursive(M)
                                    catch _:_ -> V
                                    end,
                      Acc#{K => MaybeMapped};
                  (K, V, Acc) ->
                      Acc#{K => V}
              end, #{}, Map).

internal_recursive(List) ->
    internal_recursive(List, []).

internal_recursive([], Acc) -> Acc;
internal_recursive([H | T], Acc) ->
    MaybeMapped = try maps:from_list(H) of
                      M -> from_list_recursive(M)
                  catch _:_ -> H
                  end,
    internal_recursive(T, [MaybeMapped | Acc]).

to_binary(Value) when is_list(Value) -> unicode:characters_to_binary(Value);
to_binary(Value) when is_integer(Value) -> erlang:integer_to_binary(Value);
to_binary(Value) when is_atom(Value) -> erlang:atom_to_binary(Value).