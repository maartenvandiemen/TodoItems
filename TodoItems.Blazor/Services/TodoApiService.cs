using System.Net.Http.Json;
using Microsoft.Extensions.Http;
using TodoItems.Blazor.Models;

namespace TodoItems.Blazor.Services;

public class TodoApiService
{
    private readonly HttpClient _http;

    public List<TodoItem> Items { get; private set; } = [];

    private FilterOption _filter = FilterOption.All;
    public FilterOption Filter
    {
        get => _filter;
        set { _filter = value; Notify(); }
    }

    public bool IsLoading { get; private set; }
    public string? ErrorMessage { get; private set; }

    public IEnumerable<TodoItem> FilteredItems => Filter switch
    {
        FilterOption.Active    => Items.Where(i => !i.IsComplete),
        FilterOption.Completed => Items.Where(i => i.IsComplete),
        _                      => Items
    };

    public int ActiveCount => Items.Count(i => !i.IsComplete);

    public event Action? StateChanged;

    public TodoApiService(IHttpClientFactory factory)
    {
        _http = factory.CreateClient("TodoApi");
    }

    public async Task LoadItemsAsync()
    {
        IsLoading = true;
        ErrorMessage = null;
        Notify();

        try
        {
            Items = await _http.GetFromJsonAsync<List<TodoItem>>("todoitems") ?? [];
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load items: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
            Notify();
        }
    }

    public async Task AddItemAsync(string name)
    {
        var request = new CreateTodoRequest(name);
        try
        {
            var response = await _http.PostAsJsonAsync("todoitems", request);
            if (response.IsSuccessStatusCode)
            {
                var created = await response.Content.ReadFromJsonAsync<TodoItem>();
                if (created is not null)
                {
                    Items.Add(created);
                    Notify();
                }
            }
            else
            {
                ErrorMessage = $"Failed to add item (HTTP {(int)response.StatusCode}).";
                Notify();
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to add item: {ex.Message}";
            Notify();
        }
    }

    public async Task ToggleItemAsync(TodoItem item)
    {
        // Optimistic update
        var updated = item with { IsComplete = !item.IsComplete };
        var index = Items.IndexOf(item);
        if (index >= 0) Items[index] = updated;
        Notify();

        try
        {
            var response = await _http.PutAsJsonAsync(
                $"todoitems/{item.Id}",
                new UpdateTodoRequest(item.Name, updated.IsComplete));

            if (!response.IsSuccessStatusCode)
            {
                // Rollback
                if (index >= 0) Items[index] = item;
                ErrorMessage = response.StatusCode == System.Net.HttpStatusCode.NotFound
                    ? "Item no longer exists. Refreshing list..."
                    : $"Failed to update item (HTTP {(int)response.StatusCode}).";
                Notify();
                if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                    await LoadItemsAsync();
            }
        }
        catch (Exception ex)
        {
            // Rollback
            if (index >= 0) Items[index] = item;
            ErrorMessage = $"Failed to update item: {ex.Message}";
            Notify();
        }
    }

    public async Task DeleteItemAsync(TodoItem item)
    {
        // Optimistic update
        Items.Remove(item);
        Notify();

        try
        {
            var response = await _http.DeleteAsync($"todoitems/{item.Id}");

            if (!response.IsSuccessStatusCode)
            {
                if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                {
                    ErrorMessage = "Item was already deleted. Refreshing list...";
                    Notify();
                    await LoadItemsAsync();
                }
                else
                {
                    // Rollback
                    Items.Add(item);
                    Items = [.. Items.OrderBy(i => i.Id)];
                    ErrorMessage = $"Failed to delete item (HTTP {(int)response.StatusCode}).";
                    Notify();
                }
            }
        }
        catch (Exception ex)
        {
            // Rollback
            Items.Add(item);
            Items = [.. Items.OrderBy(i => i.Id)];
            ErrorMessage = $"Failed to delete item: {ex.Message}";
            Notify();
        }
    }

    public void DismissError()
    {
        ErrorMessage = null;
        Notify();
    }

    private void Notify() => StateChanged?.Invoke();
}
