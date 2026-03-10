namespace TodoItems.Blazor.Models;

public record TodoItem(int Id, string? Name, bool IsComplete);
public record CreateTodoRequest(string Name);
public record UpdateTodoRequest(string? Name, bool IsComplete);
