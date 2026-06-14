def flatten(nested_list):
    """
    Flattens a nested list.

    :param nested_list: List containing elements and/or other lists.
    :return: A flat list with all the elements from the nested list.
    """
    flat_list = []
    for element in nested_list:
        if isinstance(element, list):
            flat_list.extend(flatten(element))
        else:
            flat_list.append(element)
    return flat_list
